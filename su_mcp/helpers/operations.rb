module SketchupMCP
  module Operations
    # Track processed requests to prevent duplicates
    @processed_requests = {}
    @request_cleanup_timer = Time.now
    
    def self.create_long_running_operation(operation, pending_operations, operation_counter)
      operation_id = "op_#{operation_counter}_#{Time.now.to_i}"
      
      # Check for duplicate requests
      request_hash = operation[:request].hash
      if @processed_requests[request_hash] && 
         (Time.now - @processed_requests[request_hash]) < 5.0  # Within 5 seconds
        Logging.log "Duplicate request detected (hash: #{request_hash}), skipping"
        return nil
      end
      
      # Mark this request as processed
      @processed_requests[request_hash] = Time.now
      
      # Clean up old processed requests periodically
      if Time.now - @request_cleanup_timer > 30.0  # Every 30 seconds
        @processed_requests.delete_if { |hash, time| Time.now - time > 60.0 }
        @request_cleanup_timer = Time.now
      end
      
      pending_operations[operation_id] = {
        id: operation_id,
        type: operation[:type],
        request: operation[:request],
        client_id: operation[:client_id],
        created_at: Time.now,
        status: :pending,
        attempts: 0,
        last_attempt_at: nil,
        error_message: nil,
        result: nil
      }
      
      Logging.log "Created long-running operation #{operation_id} for client #{operation[:client_id]}"
      return operation_id
    end
    
    def self.execute_long_running_operation(operation_id, pending_operations, active_clients)
      operation_info = pending_operations[operation_id]
      return unless operation_info
      
      operation_info[:status] = :running
      operation_info[:attempts] += 1
      operation_info[:last_attempt_at] = Time.now
      
      Logging.log "Starting execution of operation #{operation_id} (attempt #{operation_info[:attempts]})"
      
      # Send immediate acknowledgment to client that operation is running
      send_operation_status_update(operation_info, "Operation started, processing...", active_clients)
      
      # Parse the request
      begin
        parsed_request = JSON.parse(operation_info[:request])
        
        # Extract request ID
        original_id = Validation.extract_request_id(operation_info[:request], parsed_request)
        
        # Determine timeout based on operation complexity
        timeout_duration = Validation.determine_operation_timeout(parsed_request)
        Logging.log "Setting timeout to #{timeout_duration}s for this operation"
        
        # Execute the tool request directly with timeout
        response = nil
        begin
          Logging.log "About to execute handle_tool_request..."
          
          # Execute directly with timeout
          Timeout::timeout(timeout_duration) do
            response = handle_tool_request(parsed_request)
            Logging.log "Tool request completed successfully with result: #{response.inspect}"
          end
          
          Logging.log "Operation execution completed successfully"
          
          # Mark operation as completed
          operation_info[:status] = :completed
          operation_info[:result] = response
          
          Logging.log "About to send operation result..."
          # Send the response back to the client
          send_operation_result(operation_info, active_clients)
          Logging.log "Operation result sent successfully"
          
        rescue Timeout::Error
          Logging.log "Request processing timeout after #{timeout_duration}s"
          
          # Mark operation as failed
          operation_info[:status] = :failed
          operation_info[:error_message] = "Operation timeout"
          send_operation_error(operation_info, active_clients)
        rescue StandardError => e
          Logging.log "Request processing error: #{e.message}"
          Logging.log "Processing error backtrace: #{e.backtrace.join("\n")}"
          
          # Mark operation as failed
          operation_info[:status] = :failed
          operation_info[:error_message] = e.message
          send_operation_error(operation_info, active_clients)
        end
      rescue StandardError => e
        Logging.log "Operation #{operation_id} failed: #{e.message}"
        Logging.log "Operation failure backtrace: #{e.backtrace.join("\n")}"
        operation_info[:error_message] = e.message
        operation_info[:status] = :failed
        send_operation_error(operation_info, active_clients)
      end
    end
    
    def self.retry_failed_operation_by_id(operation_id, pending_operations)
      operation_info = pending_operations[operation_id]
      return unless operation_info && operation_info[:status] == :failed
      
      Logging.log "Retrying failed operation #{operation_id}"
      execute_long_running_operation(operation_id, pending_operations)
    end
    
    def self.mark_operation_failed(operation_id, error_message, pending_operations)
      operation_info = pending_operations[operation_id]
      return unless operation_info
      
      operation_info[:status] = :failed
      operation_info[:error_message] = error_message
      Logging.log "Marked operation #{operation_id} as failed: #{error_message}"
    end
    
    def self.cleanup_old_pending_operations(pending_operations, max_operation_time, active_clients)
      now = Time.now
      operations_to_clean = []
      
      pending_operations.each do |operation_id, operation_info|
        # Check if operation has been running for more than max time
        if operation_info[:status] == :running && 
           operation_info[:last_attempt_at] && 
           (now - operation_info[:last_attempt_at]) > max_operation_time
          
          Logging.log "Operation #{operation_id} exceeded maximum runtime (#{max_operation_time}s), marking as failed"
          operation_info[:status] = :failed
          operation_info[:error_message] = "Operation exceeded maximum runtime"
          operations_to_clean << operation_id
          
          # Send timeout error to client
          send_operation_error(operation_info, active_clients)
        end
        
        # Clean up very old completed or failed operations
        if [:completed, :failed].include?(operation_info[:status]) &&
           (now - operation_info[:created_at]) > 300  # 5 minutes
          
          Logging.log "Cleaning up old operation #{operation_id}"
          operations_to_clean << operation_id
        end
      end
      
      # Remove cleaned operations
      operations_to_clean.each { |id| pending_operations.delete(id) }
    end
    
    def self.send_operation_status_update(operation_info, message, active_clients)
      client_info = active_clients[operation_info[:client_id]]
      return unless client_info
      
      status_response = {
        jsonrpc: "2.0",
        method: "operation/status",
        params: {
          operation_id: operation_info[:id],
          status: operation_info[:status].to_s,
          message: message,
          timestamp: Time.now.to_f
        }
      }
      
      success = send_response(client_info[:socket], status_response)
      if !success
        Logging.log "Failed to send status update for operation #{operation_info[:id]} - client may have disconnected"
        # Remove client from active clients if send failed
        active_clients.delete(operation_info[:client_id])
      end
    end
    
    def self.send_operation_result(operation_info, active_clients)
      client_info = active_clients[operation_info[:client_id]]
      return unless client_info
      
      # Try to extract original request ID for proper JSON-RPC response
      original_id = nil
      begin
        if operation_info[:request]
          parsed_request = JSON.parse(operation_info[:request])
          original_id = parsed_request["id"]
        end
      rescue
        # Ignore parsing errors
      end
      
      result_response = {
        jsonrpc: "2.0",
        result: operation_info[:result],
        id: original_id
      }
      
      success = send_response(client_info[:socket], result_response)
      if success
        Logging.log "Sent result for operation #{operation_info[:id]} to client #{operation_info[:client_id]}"
      else
        Logging.log "Failed to send result for operation #{operation_info[:id]} - client may have disconnected"
        # Remove client from active clients if send failed
        active_clients.delete(operation_info[:client_id])
      end
    end
    
    def self.send_operation_error(operation_info, active_clients)
      client_info = active_clients[operation_info[:client_id]]
      return unless client_info
      
      # Try to extract original request ID for proper JSON-RPC response
      original_id = nil
      begin
        if operation_info[:request]
          parsed_request = JSON.parse(operation_info[:request])
          original_id = parsed_request["id"]
        end
      rescue
        # Ignore parsing errors
      end
      
      error_response = {
        jsonrpc: "2.0",
        error: {
          code: -32603,
          message: "Operation failed: #{operation_info[:error_message]}",
          data: {
            operation_id: operation_info[:id],
            attempts: operation_info[:attempts]
          }
        },
        id: original_id
      }
      
      success = send_response(client_info[:socket], error_response)
      if success
        Logging.log "Sent error for operation #{operation_info[:id]} to client #{operation_info[:client_id]}"
      else
        Logging.log "Failed to send error for operation #{operation_info[:id]} - client may have disconnected"
        # Remove client from active clients if send failed
        active_clients.delete(operation_info[:client_id])
      end
    end
    
    def self.handle_tool_request(parsed_request)
      Logging.log "Handling tool request: #{parsed_request.inspect}"
      
      method = parsed_request["method"]
      params = parsed_request["params"] || {}
      
      unless method == "tools/call"
        raise "Unsupported method: #{method}"
      end
      
      tool_name = params["name"]
      arguments = params["arguments"] || {}
      
      Logging.log "Dispatching tool: #{tool_name} with arguments: #{arguments.inspect}"
      
      # Dispatch to the appropriate tool module
      result = case tool_name
      when "create_component"
        SketchupMCP::ComponentTools.create_component(arguments)
      when "delete_component"
        SketchupMCP::ComponentTools.delete_component(arguments)
      when "transform_component"
        SketchupMCP::ComponentTools.transform_component(arguments)
      when "get_selection"
        SketchupMCP::ComponentTools.get_selection
      when "set_material"
        SketchupMCP::MaterialTools.set_material(arguments)
      when "boolean_operation"
        SketchupMCP::BooleanTools.boolean_operation(arguments)
      when "create_mortise_tenon"
        SketchupMCP::WoodworkingTools.create_mortise_tenon(arguments)
      when "create_dovetail"
        SketchupMCP::WoodworkingTools.create_dovetail(arguments)
      when "create_finger_joint"
        SketchupMCP::WoodworkingTools.create_finger_joint(arguments)
      when "chamfer_edges"
        SketchupMCP::EdgeTools.chamfer_edges(arguments)
      when "fillet_edges"
        SketchupMCP::EdgeTools.fillet_edges(arguments)
      when "export"
        SketchupMCP::ExportTools.export(arguments)
      when "eval_ruby"
        SketchupMCP::RubyEval.eval_ruby_with_yielding(arguments)
      when "calculate_distance"
        SketchupMCP::MeasurementTools.calculate_distance(arguments)
      when "measure_components"
        SketchupMCP::MeasurementTools.measure_components(arguments)
      when "inspect_component"
        SketchupMCP::MeasurementTools.inspect_component(arguments)
      when "create_reference_markers"
        SketchupMCP::MeasurementTools.create_reference_markers(arguments)
      when "clear_reference_markers"
        SketchupMCP::MeasurementTools.clear_reference_markers(arguments)
      when "snap_align_component"
        SketchupMCP::MeasurementTools.snap_align_component(arguments)
      when "create_grid_system"
        SketchupMCP::MeasurementTools.create_grid_system(arguments)
      when "query_all_components"
        SketchupMCP::MeasurementTools.query_all_components(arguments)
      when "position_relative_to_component"
        SketchupMCP::MeasurementTools.position_relative_to_component(arguments)
      when "position_between_components"
        SketchupMCP::MeasurementTools.position_between_components(arguments)
      when "show_component_bounds"
        SketchupMCP::MeasurementTools.show_component_bounds(arguments)
      when "create_component_with_verification"
        SketchupMCP::MeasurementTools.create_component_with_verification(arguments)
      when "preview_position"
        SketchupMCP::MeasurementTools.preview_position(arguments)
      else
        raise "Unknown tool: #{tool_name}"
      end
      
      Logging.log "Tool execution completed with result: #{result.inspect}"
      return result
    end
    
    private
    
    def self.send_response(client, response)
      begin
        response_json = response.to_json + "\n"
        Logging.log "Sending response: #{response_json.strip}"
        
        # Check if client socket is valid before writing
        if client.nil?
          Logging.log "Error: Client socket is nil"
          return false
        end
        
        # Check if socket is still open before trying to write
        begin
          # Try to check socket status
          client.stat if client.respond_to?(:stat)
        rescue => e
          Logging.log "Socket appears to be closed: #{e.message}"
          return false
        end
        
        # Test if socket is still open
        begin
          bytes_written = client.write(response_json)
          Logging.log "Wrote #{bytes_written} bytes to client"
          client.flush
          
          # Small delay to prevent race conditions
          sleep(0.01)
          
          Logging.log "Response sent successfully"
          return true
        rescue Errno::EPIPE, Errno::ECONNRESET, IOError => e
          Logging.log "Client connection closed during response send: #{e.message}"
          return false
        rescue StandardError => e
          Logging.log "Error writing to client socket: #{e.message}"
          Logging.log "Socket error backtrace: #{e.backtrace.join("\n")}"
          return false
        end
      rescue StandardError => e
        Logging.log "Error preparing response: #{e.message}"
        Logging.log "Response preparation backtrace: #{e.backtrace.join("\n")}"
        return false
      end
    end
  end
end 