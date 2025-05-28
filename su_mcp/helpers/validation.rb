module SketchupMCP
  module Validation
    def self.validate_and_normalize_params(position, dimensions, component_type = nil, direction = "up", origin_mode = "center")
      Logging.log "Raw parameters - position: #{position.inspect} (#{position.class}), dimensions: #{dimensions.inspect} (#{dimensions.class}), type: #{component_type}, direction: #{direction}, origin_mode: #{origin_mode}"
      
      # Validate direction parameter
      valid_directions = ["up", "down", "forward", "back", "right", "left", "auto"]
      unless valid_directions.include?(direction.to_s.downcase)
        Logging.log "Warning: Invalid direction '#{direction}', using 'up'"
        direction = "up"
      else
        direction = direction.to_s.downcase
      end
      
      # Validate origin_mode parameter
      valid_origin_modes = ["center", "bottom_center", "top_center", "min_corner", "max_corner"]
      unless valid_origin_modes.include?(origin_mode.to_s.downcase)
        Logging.log "Warning: Invalid origin_mode '#{origin_mode}', using 'center'"
        origin_mode = "center"
      else
        origin_mode = origin_mode.to_s.downcase
      end
      
      # Convert to arrays and ensure numeric values
      pos = Array(position || [0,0,0]).map do |val|
        begin
          val.to_f
        rescue StandardError => e
          Logging.log "Warning: Could not convert position value #{val.inspect} to float, using 0.0. Error: #{e.message}"
          0.0
        end
      end
      
      dims = Array(dimensions || [1,1,1]).map do |val|
        begin
          val.to_f
        rescue StandardError => e
          Logging.log "Warning: Could not convert dimension value #{val.inspect} to float, using 1.0. Error: #{e.message}"
          1.0
        end
      end
      
      Logging.log "After conversion - position: #{pos.inspect}, dimensions: #{dims.inspect}, direction: #{direction}, origin_mode: #{origin_mode}"
      
      # Ensure we have at least 3 dimensions, pad with appropriate values based on component type
      while pos.length < 3
        pos << 0.0
      end
      
      # Handle dimensions based on component type and current length
      if dims.length == 2
        case component_type
        when "cylinder", "cone"
          # For cylinder/cone: [diameter, height] -> [diameter, diameter, height]
          # This way radius = dims[0]/2 and height = dims[2] works correctly
          dims = [dims[0], dims[0], dims[1]]
          Logging.log "Adjusted cylinder/cone dimensions from 2D to 3D: #{dims.inspect}"
        when "sphere"
          # For sphere: [diameter, height] -> [diameter, diameter, diameter] 
          dims = [dims[0], dims[0], dims[0]]
          Logging.log "Adjusted sphere dimensions from 2D to 3D: #{dims.inspect}"
        else
          # For cube and other shapes: [width, height] -> [width, height, height]
          dims = [dims[0], dims[1], dims[1]]
          Logging.log "Adjusted general dimensions from 2D to 3D: #{dims.inspect}"
        end
      elsif dims.length == 1
        # Single dimension: make it cubic/spherical
        dims = [dims[0], dims[0], dims[0]]
        Logging.log "Adjusted single dimension to 3D: #{dims.inspect}"
      end
      
      # Ensure we have exactly 3 dimensions, pad with default values if needed
      while dims.length < 3
        # Use the last available dimension as default, or 1.0 if none
        default_dim = dims.last || 1.0
        dims << default_dim
        Logging.log "Padded dimensions with #{default_dim}, now: #{dims.inspect}"
      end
      
      # Validate that all dimensions are positive
      dims.each_with_index do |dim, index|
        if dim <= 0
          Logging.log "Warning: Dimension[#{index}] was #{dim}, adjusting to 1.0"
          dims[index] = 1.0
        end
      end
      
      Logging.log "Final normalized - position: #{pos.inspect}, dimensions: #{dims.inspect}, direction: #{direction}, origin_mode: #{origin_mode}"
      return pos, dims, direction, origin_mode
    end

    def self.calculate_origin_position(requested_position, dimensions, origin_mode)
      """Calculate the actual center position based on origin_mode and requested position"""
      
      width, height, depth = dimensions
      half_width = width / 2.0
      half_height = height / 2.0  
      half_depth = depth / 2.0
      
      case origin_mode
      when "center"
        # Position is already the center - no adjustment needed
        return requested_position
        
      when "bottom_center"
        # Position is bottom-center, so we need to move center up by half depth (Z-dimension)
        return [requested_position[0], requested_position[1], requested_position[2] + half_depth]
        
      when "top_center"
        # Position is top-center, so we need to move center down by half depth (Z-dimension)
        return [requested_position[0], requested_position[1], requested_position[2] - half_depth]
        
      when "min_corner"
        # Position is min corner (x_min, y_min, z_min), so center is offset by half dimensions
        return [requested_position[0] + half_width, requested_position[1] + half_height, requested_position[2] + half_depth]
        
      when "max_corner"
        # Position is max corner (x_max, y_max, z_max), so center is offset by negative half dimensions
        return [requested_position[0] - half_width, requested_position[1] - half_height, requested_position[2] - half_depth]
        
      else
        Logging.log "Warning: Unknown origin_mode '#{origin_mode}', using center"
        return requested_position
      end
    end

    def self.get_extrusion_vector(direction, magnitude)
      """Get the extrusion vector based on direction and magnitude"""
      
      case direction
      when "up"
        return [0, 0, magnitude]
      when "down"
        return [0, 0, -magnitude]
      when "forward"
        return [0, magnitude, 0]
      when "back"
        return [0, -magnitude, 0]
      when "right"
        return [magnitude, 0, 0]
      when "left"
        return [-magnitude, 0, 0]
      when "auto"
        # Auto defaults to up for most cases
        return [0, 0, magnitude]
      else
        Logging.log "Warning: Unknown direction '#{direction}', using up"
        return [0, 0, magnitude]
      end
    end

    def self.point_inside_bounds?(point, bounds)
      return (point.x >= bounds.min.x && point.x <= bounds.max.x &&
              point.y >= bounds.min.y && point.y <= bounds.max.y &&
              point.z >= bounds.min.z && point.z <= bounds.max.z)
    end

    def self.extract_request_id(data, parsed_request)
      # Try to get ID from parsed request first
      if parsed_request && parsed_request["id"]
        return parsed_request["id"]
      end
      
      # Fall back to regex parsing
      if data =~ /"id":\s*(\d+)/
        return $1.to_i
      end
      
      nil
    end

    def self.determine_operation_timeout(request)
      # Determine appropriate timeout based on the request complexity
      method = request["method"]
      
      case method
      when "tools/call"
        tool_name = request.dig("params", "name")
        arguments = request.dig("params", "arguments")
        
        case tool_name
        when "eval_ruby"
          # Analyze the Ruby code to determine complexity
          code = arguments&.dig("code") || ""
          
          # Count potential complexity indicators
          geometry_operations = code.scan(/add_face|add_group|add_instance|pushpull|transform|intersect_with/).length
          loop_operations = code.scan(/\.times|\.each|\.map|for\s+\w+\s+in|while|loop/).length
          large_numbers = code.scan(/\d+/).map(&:to_i).select { |n| n > 100 }.length
          code_length = code.length
          
          # Much more generous timeouts for complex operations
          if geometry_operations > 50 || loop_operations > 10 || large_numbers > 10 || code_length > 5000
            600.0  # 10 minutes for very complex operations
          elsif geometry_operations > 20 || loop_operations > 5 || large_numbers > 5 || code_length > 2000
            300.0  # 5 minutes for complex operations
          elsif geometry_operations > 5 || loop_operations > 2 || code_length > 1000
            180.0  # 3 minutes for moderate operations
          else
            120.0  # 2 minutes for simple operations
          end
          
        when "create_component"
          # Component creation can be complex depending on geometry
          60.0  # 1 minute
          
        when "boolean_operation", "create_dovetail", "create_mortise_tenon", "create_finger_joint"
          # Complex woodworking operations need much more time
          180.0  # 3 minutes
          
        when "chamfer_edges", "fillet_edges"
          # Edge operations can be very complex with many edges
          120.0  # 2 minutes
          
        when "export", "export_scene"
          # Export operations can take time depending on model complexity
          180.0  # 3 minutes
          
        else
          # Default timeout for unknown tools - be generous
          120.0  # 2 minutes
        end
        
      when "resources/list"
        # Resource listing can be slow for very large models
        60.0  # 1 minute
        
      when "ping", "test_connection"
        # Simple operations
        30.0  # 30 seconds
        
      else
        # Default timeout - be generous
        120.0  # 2 minutes
      end
    end
  end
end 