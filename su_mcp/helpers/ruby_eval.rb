module SketchupMCP
  module RubyEval
    def self.eval_ruby_with_yielding(params)
      Logging.log "Evaluating Ruby code with enhanced main-thread chunking - length: #{params['code'].length}"
      
      begin
        code = params["code"]
        
        # Ensure model is in clean state
        model = Sketchup.active_model
        
        # Detect operations that need chunking
        requirements = detect_yielding_requirements(code)
        
        if requirements[:required] && requirements[:complexity] != :simple
          Logging.log "Code requires chunking - #{requirements[:reason]} (complexity: #{requirements[:complexity]})"
          
          # For complex operations, use the new chunked system
          # But since we're already in a tool call, execute it directly with enhanced yielding
          if requirements[:complexity] == :extreme
            Logging.log "Using aggressive chunking for extremely complex operation"
            result = execute_with_enhanced_chunking(code, requirements)
          else
            # Create yielding wrapper based on operation type
            wrapped_code = create_yielding_wrapper(code, requirements)
            
            # Execute with a model operation to ensure thread safety
            result = execute_with_operation(wrapped_code, requirements)
          end
        else
          Logging.log "Simple code - executing directly with basic safety"
          
          # Even simple code should be in an operation for safety
          if model && code.match?(/(entities\.|add_|create_|transform|pushpull)/)
            operation_name = "MCP Ruby Eval"
            model.start_operation(operation_name, true)
            begin
              result = eval(code, TOPLEVEL_BINDING.dup)
              model.commit_operation
            rescue StandardError => e
              model.abort_operation
              raise e
            end
          else
            result = eval(code, TOPLEVEL_BINDING.dup)
          end
        end
        
        Logging.log "Code evaluation completed with result: #{result.inspect}"
        
        # Return success with the result as a string
        { 
          success: true,
          result: result.to_s
        }
      rescue StandardError => e
        Logging.log "Error in eval_ruby_with_yielding: #{e.message}"
        Logging.log e.backtrace.join("\n")
        
        raise "Ruby evaluation error: #{e.message}"
      end
    end
    
    def self.execute_with_enhanced_chunking(code, requirements)
      Logging.log "Executing with enhanced chunking for extremely complex operation"
      model = Sketchup.active_model
      
      # Use the same chunking logic as the async version, but execute synchronously
      chunks = analyze_and_chunk_ruby_code(code)
      Logging.log "Split code into #{chunks.length} chunks for synchronous execution"
      
      results = []
      operation_name = "MCP Complex Eval (Chunked)"
      
      chunks.each_with_index do |chunk, index|
        Logging.log "Executing synchronous chunk #{index + 1}/#{chunks.length}"
        
        begin
          # Each chunk gets its own operation
          if model && chunk.match?(/(entities\.|add_|create_|transform|pushpull)/)
            model.start_operation("#{operation_name} #{index + 1}", true)
            
            # Execute chunk
            chunk_result = eval(chunk, TOPLEVEL_BINDING.dup)
            
            model.commit_operation
          else
            chunk_result = eval(chunk, TOPLEVEL_BINDING.dup)
          end
          
          results << chunk_result
          
          # Force view refresh and yield between chunks
          if index % 2 == 0 && model  # Every 2 chunks
            model.active_view.invalidate
            
            # Small delay to let SketchUp process UI events
            start_time = Time.now
            while (Time.now - start_time) < 0.05  # 50ms delay
              # Busy wait to yield CPU
            end
          end
          
        rescue StandardError => e
          if model
            model.abort_operation rescue nil
          end
          raise "Error in chunk #{index + 1}: #{e.message}"
        end
      end
      
      # Return the last result or a summary
      if results.any? { |r| r.to_s.include?("COMPLETE") || r.to_s.include?("ready") }
        results.find { |r| r.to_s.include?("COMPLETE") || r.to_s.include?("ready") }
      else
        results.last || "Chunked operation completed (#{chunks.length} chunks)"
      end
    end
    
    def self.detect_yielding_requirements(code)
      requirements = {
        required: false,
        reason: nil,
        complexity: :simple,
        estimated_time: :short,
        geometry_operations: 0,
        loop_operations: 0
      }
      
      # Count geometry operations more thoroughly
      geometry_patterns = [
        /add_face\s*\(/, /add_group\s*\(/, /add_instance\s*\(/, 
        /add_line\s*\(/, /add_cpoint\s*\(/, /add_cline\s*\(/,
        /add_curve\s*\(/, /add_arc\s*\(/, /add_circle\s*\(/,
        /add_polygon\s*\(/, /pushpull\s*\(/, /followme\s*\(/,
        /intersect_with\s*\(/, /transform!\s*\(/, /erase!\s*\(/,
        /material\s*=/, /\.copy\s*\(/, /\.explode\s*\(/
      ]
      
      geometry_count = geometry_patterns.sum { |pattern| code.scan(pattern).length }
      requirements[:geometry_operations] = geometry_count
      
      # Count loop constructs more thoroughly
      loop_patterns = [
        /\d+\.times\s*[\{\|]/, /\.each\s*[\{\|]/, /\.map\s*[\{\|]/,
        /\.select\s*[\{\|]/, /for\s+\w+\s+in/, /while\s+/,
        /loop\s*[\{\|]/, /until\s+/, /\.upto\s*[\{\|]/,
        /\.downto\s*[\{\|]/, /\.step\s*[\{\|]/
      ]
      
      loop_count = loop_patterns.sum { |pattern| code.scan(pattern).length }
      requirements[:loop_operations] = loop_count
      
      # Check for nested operations (loops containing geometry operations)
      nested_operations = 0
      if loop_count > 0 && geometry_count > 0
        # Rough heuristic: if we have both loops and geometry, assume some nesting
        nested_operations = [loop_count, geometry_count].min
      end
      
      # More aggressive complexity detection
      if nested_operations > 0
        requirements[:required] = true
        if nested_operations > 5 || geometry_count > 50
          requirements[:complexity] = :extreme
          requirements[:reason] = "nested geometry operations (#{nested_operations} nested, #{geometry_count} total geometry)"
          requirements[:estimated_time] = :very_long
        elsif nested_operations > 2 || geometry_count > 20
          requirements[:complexity] = :high
          requirements[:reason] = "significant nested geometry (#{nested_operations} nested, #{geometry_count} total)"
          requirements[:estimated_time] = :long
        else
          requirements[:complexity] = :moderate
          requirements[:reason] = "moderate nested geometry (#{nested_operations} nested)"
          requirements[:estimated_time] = :medium
        end
      elsif geometry_count > 100
        requirements[:required] = true
        requirements[:complexity] = :extreme
        requirements[:reason] = "massive geometry operations (#{geometry_count})"
        requirements[:estimated_time] = :very_long
      elsif geometry_count > 30
        requirements[:required] = true
        requirements[:complexity] = :high
        requirements[:reason] = "many geometry operations (#{geometry_count})"
        requirements[:estimated_time] = :long
      elsif geometry_count > 10
        requirements[:required] = true
        requirements[:complexity] = :moderate
        requirements[:reason] = "moderate geometry operations (#{geometry_count})"
        requirements[:estimated_time] = :medium
      elsif loop_count > 3
        requirements[:required] = true
        requirements[:complexity] = :moderate
        requirements[:reason] = "multiple loops (#{loop_count})"
        requirements[:estimated_time] = :medium
      elsif loop_count > 0
        requirements[:required] = true
        requirements[:complexity] = :simple
        requirements[:reason] = "contains loops (#{loop_count})"
        requirements[:estimated_time] = :short
      end
      
      # Check for large numeric values that might indicate heavy operations
      large_numbers = code.scan(/(\d+)/).flatten.map(&:to_i).select { |n| n > 50 }
      if large_numbers.any?
        max_number = large_numbers.max
        if max_number > 1000
          requirements[:required] = true
          requirements[:complexity] = [:extreme, requirements[:complexity]].max_by { |c| [:simple, :moderate, :high, :extreme].index(c) }
          requirements[:reason] = (requirements[:reason] || "") + " + large numbers (max: #{max_number})"
          requirements[:estimated_time] = :very_long
        elsif max_number > 100
          requirements[:required] = true
          requirements[:complexity] = [:high, requirements[:complexity]].max_by { |c| [:simple, :moderate, :high, :extreme].index(c) }
          requirements[:reason] = (requirements[:reason] || "") + " + large numbers (max: #{max_number})"
        end
      end
      
      # Check code length
      if code.length > 5000
        requirements[:required] = true
        requirements[:complexity] = [:extreme, requirements[:complexity]].max_by { |c| [:simple, :moderate, :high, :extreme].index(c) }
        requirements[:reason] = (requirements[:reason] || "") + " + massive code (#{code.length} chars)"
        requirements[:estimated_time] = :very_long
      elsif code.length > 2000
        requirements[:required] = true
        requirements[:complexity] = [:high, requirements[:complexity]].max_by { |c| [:simple, :moderate, :high, :extreme].index(c) }
        requirements[:reason] = (requirements[:reason] || "") + " + large code (#{code.length} chars)"
      end
      
      requirements
    end
    
    def self.analyze_and_chunk_ruby_code(code)
      lines = code.split("\n")
      chunks = []
      current_chunk = []
      geometry_ops_in_chunk = 0
      max_geometry_ops_per_chunk = 5  # Limit geometry operations per chunk
      
      lines.each do |line|
        # Skip comments and empty lines for analysis
        clean_line = line.strip
        next if clean_line.empty? || clean_line.start_with?('#')
        
        # Check if this line contains geometry operations
        is_geometry_op = line.match?(/(add_face|add_group|add_instance|pushpull|transform|erase!)/)
        
        # If adding this line would exceed our geometry op limit, finalize current chunk
        if is_geometry_op && geometry_ops_in_chunk >= max_geometry_ops_per_chunk && !current_chunk.empty?
          chunks << current_chunk.join("\n")
          current_chunk = []
          geometry_ops_in_chunk = 0
        end
        
        current_chunk << line
        geometry_ops_in_chunk += 1 if is_geometry_op
        
        # Also chunk on natural break points
        if line.match?(/^end\s*$/) || line.match?(/^}\s*$/) || line.include?('puts ')
          # This is a natural break point, consider chunking here if we have enough content
          if current_chunk.length > 10 || geometry_ops_in_chunk > 2
            chunks << current_chunk.join("\n")
            current_chunk = []
            geometry_ops_in_chunk = 0
          end
        end
      end
      
      # Add any remaining lines as final chunk
      unless current_chunk.empty?
        chunks << current_chunk.join("\n")
      end
      
      # If we only got one chunk, split it more aggressively
      if chunks.length == 1 && lines.length > 20
        chunks = split_large_chunk_aggressively(chunks[0])
      end
      
      chunks
    end
    
    def self.split_large_chunk_aggressively(code)
      lines = code.split("\n")
      chunks = []
      lines_per_chunk = [15, lines.length / 4].min  # Max 15 lines per chunk, or quarter of total
      
      lines.each_slice(lines_per_chunk) do |chunk_lines|
        chunks << chunk_lines.join("\n")
      end
      
      chunks
    end
    
    def self.create_yielding_wrapper(code, requirements)
      case requirements[:complexity]
      when :extreme
        %{
          # Extreme complexity yielding wrapper
          yield_counter = 0
          last_refresh = Time.now
          
          def yield_aggressively
            yield_counter += 1
            if yield_counter % 1 == 0  # Yield after EVERY operation
              sleep(0.002)
              if yield_counter % 5 == 0  # Refresh view every 5 operations
                begin
                  Sketchup.active_model.active_view.invalidate
                rescue
                  # Ignore errors
                end
              end
            end
          end
          
          def yield_very_frequently
            yield_counter += 1
            if yield_counter % 2 == 0  # Yield every 2 operations
              sleep(0.001)
            end
          end
          
          #{inject_yielding_calls(code, :aggressive)}
        }
      when :high
        %{
          # High complexity yielding wrapper
          yield_counter = 0
          
          def yield_frequently
            yield_counter += 1
            if yield_counter % 2 == 0  # Yield every 2 operations
              sleep(0.001)
              if yield_counter % 10 == 0  # Refresh view every 10 operations
                begin
                  Sketchup.active_model.active_view.invalidate
                rescue
                  # Ignore errors
                end
              end
            end
          end
          
          def yield_occasionally
            yield_counter += 1
            if yield_counter % 5 == 0  # Yield every 5 operations
              sleep(0.001)
            end
          end
          
          #{inject_yielding_calls(code, :frequent)}
        }
      when :moderate
        %{
          # Moderate complexity yielding wrapper
          yield_counter = 0
          
          def yield_occasionally
            yield_counter += 1
            if yield_counter % 8 == 0  # Yield every 8 operations
              sleep(0.001)
              if yield_counter % 40 == 0  # Refresh view every 40 operations
                begin
                  Sketchup.active_model.active_view.invalidate
                rescue
                  # Ignore errors
                end
              end
            end
          end
          
          #{inject_yielding_calls(code, :occasional)}
        }
      else
        %{
          # Simple yielding wrapper
          yield_counter = 0
          
          def yield_occasionally
            yield_counter += 1
            if yield_counter % 15 == 0  # Yield every 15 operations
              sleep(0.001)
            end
          end
          
          #{inject_yielding_calls(code, :minimal)}
        }
      end
    end
    
    def self.inject_yielding_calls(code, frequency)
      modified_code = code.dup
      
      # Define yielding method based on frequency
      yield_method = case frequency
      when :aggressive
        "yield_aggressively"
      when :frequent
        "yield_frequently"
      when :occasional
        "yield_occasionally"
      else
        "yield_occasionally"
      end
      
      # Split code into lines to process line by line safely
      lines = modified_code.split("\n")
      processed_lines = []
      
      lines.each do |line|
        processed_line = line.dup
        
        # Only inject yields after complete statements that end with geometry operations
        # Match patterns that represent complete statements ending with method calls
        geometry_statement_patterns = [
          # Entity creation that ends a statement
          /^(\s*.*entities\.add_\w+\([^)]*\)\s*)$/,
          /^(\s*.*\.add_\w+\([^)]*\)\s*)$/,
          
          # Transformations that end a statement
          /^(\s*.*\.transform!\([^)]*\)\s*)$/,
          /^(\s*.*\.pushpull\([^)]*\)\s*)$/,
          /^(\s*.*\.followme\([^)]*\)\s*)$/,
          
          # Material assignments that end a statement
          /^(\s*.*\.material\s*=\s*[^#\n]+)$/,
          
          # Boolean operations that end a statement
          /^(\s*.*\.intersect_with\([^)]*\)\s*)$/,
          /^(\s*.*\.erase!\s*(?:\(\s*\))?\s*)$/,
          
          # Copy and explode that end a statement
          /^(\s*.*\.copy\([^)]*\)\s*)$/,
          /^(\s*.*\.explode\s*(?:\(\s*\))?\s*)$/
        ]
        
        # Check if this line contains a complete geometry statement
        geometry_statement_patterns.each do |pattern|
          if processed_line.match?(pattern)
            # Only add yield if the line doesn't already have one and doesn't end with a continuation
            unless processed_line.include?(yield_method) || processed_line.strip.end_with?('\\') || processed_line.strip.end_with?(',')
              if frequency == :aggressive
                processed_line += "; yield_aggressively"
              else
                processed_line += "; #{yield_method}"
              end
              break  # Only apply one yield per line
            end
          end
        end
        
        # Handle loop constructs - add yields at the beginning of loop blocks
        loop_start_patterns = [
          # times loops
          /^(\s*)(\d+)\.times\s*do\s*(\|[^|]*\|)?\s*$/,
          /^(\s*)(\d+)\.times\s*\{\s*(\|[^|]*\|)?\s*$/,
          # each loops  
          /^(\s*)(\w+)\.each\s*do\s*(\|[^|]*\|)?\s*$/,
          /^(\s*)(\w+)\.each\s*\{\s*(\|[^|]*\|)?\s*$/,
          # for loops
          /^(\s*)(for\s+\w+\s+in\s+[^#\n]+)\s*$/
        ]
        
        loop_start_patterns.each do |pattern|
          if processed_line.match?(pattern)
            # Add the yield call on the next line (will be added when we process subsequent lines)
            # For now, just mark this line as a loop start
            break
          end
        end
        
        processed_lines << processed_line
      end
      
      # Join lines back together
      modified_code = processed_lines.join("\n")
      
      # Add yields inside loop bodies more carefully
      if frequency == :aggressive
        # For aggressive mode, add yields after each statement inside loops
        # This is a more conservative approach that looks for complete statement lines
        loop_body_lines = []
        in_loop = false
        loop_indent = 0
        
        modified_code.split("\n").each_with_index do |line, index|
          # Detect loop start
          if line.match?(/^(\s*).*\.(times|each)\s*(do|\{)/) || line.match?(/^(\s*)for\s+\w+\s+in/)
            in_loop = true
            loop_indent = line.match(/^(\s*)/)[1].length
            loop_body_lines << line
          # Detect loop end
          elsif in_loop && (line.match(/^(\s*)(end|\})\s*$/) && line.match(/^(\s*)/)[1].length <= loop_indent)
            in_loop = false
            loop_body_lines << line
          # Inside loop body
          elsif in_loop && line.strip.length > 0 && !line.strip.start_with?('#')
            # Add yield after substantial statements inside loops
            if line.match?(/^\s*.*\.(add_|create_|transform|pushpull|material\s*=)/) && !line.include?('yield_')
              loop_body_lines << line + "; yield_very_frequently"
            else
              loop_body_lines << line
            end
          else
            loop_body_lines << line
          end
        end
        
        modified_code = loop_body_lines.join("\n")
      end
      
      modified_code
    end
    
    def self.execute_with_operation(code, requirements)
      model = Sketchup.active_model
      result = nil
      
      # Choose operation name and settings based on complexity
      operation_name, disable_ui, timeout_duration = case requirements[:complexity]
      when :extreme
        ["MCP Extreme Eval", true, 45.0]
      when :high
        ["MCP Complex Eval", true, 30.0]
      when :moderate
        ["MCP Moderate Eval", false, 20.0]
      else
        ["MCP Simple Eval", false, 10.0]
      end
      
      # Use start_operation for thread safety
      begin
        model.start_operation(operation_name, disable_ui)
        
        # Execute with timeout
        Timeout::timeout(timeout_duration) do
          result = eval(code, TOPLEVEL_BINDING.dup)
        end
        
        model.commit_operation
        
        # Force view refresh for complex operations
        if requirements[:complexity] == :extreme || requirements[:complexity] == :high
          model.active_view.invalidate
        end
        
      rescue Timeout::Error
        model.abort_operation
        raise "Ruby evaluation timeout (#{timeout_duration}s) - operation was too complex (#{requirements[:reason]})"
      rescue StandardError => e
        model.abort_operation
        raise e
      end
      
      result
    end
  end
end 