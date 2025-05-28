module SketchupMCP
  module ComponentTools
    def self.create_component(params)
      Logging.log "Creating component with params: #{params.inspect}"
      
      # Ensure we have a valid model and it's in a clean state
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      Logging.log "Got active model: #{model.inspect}"
      entities = model.active_entities
      Logging.log "Got active entities: #{entities.inspect}"
      
      # Extract directional parameters
      direction = params["direction"] || "up"
      origin_mode = params["origin_mode"] || "center"
      
      pos, dims, direction, origin_mode = Validation.validate_and_normalize_params(
        params["position"], 
        params["dimensions"], 
        params["type"],
        direction,
        origin_mode
      )
      
      Logging.log "Normalized position: #{pos.inspect}, dimensions: #{dims.inspect}, direction: #{direction}, origin_mode: #{origin_mode}"
      
      # Calculate the actual center position based on origin_mode
      center_pos = Validation.calculate_origin_position(pos, dims, origin_mode)
      Logging.log "Calculated center position: #{center_pos.inspect} (from requested position: #{pos.inspect}, origin_mode: #{origin_mode})"
      
      # Execute component creation directly without wrapping in another operation
      # The long-running operation system will handle the overall operation management
      begin
        case params["type"]
        when "cube"
          result = create_cube(entities, center_pos, dims, direction, origin_mode)
          
        when "cylinder"
          result = create_cylinder(entities, center_pos, dims, direction, origin_mode)
          
        when "sphere"
          result = create_sphere(entities, center_pos, dims, direction, origin_mode)
          
        when "cone"
          result = create_cone(entities, center_pos, dims, direction, origin_mode)
          
        else
          Logging.log "Unknown component type: #{params["type"]}"
          raise "Unknown component type: #{params["type"]}"
        end
        
        # Add directional information to the result
        result[:direction] = direction
        result[:origin_mode] = origin_mode
        result[:requested_position] = pos
        result[:calculated_center] = center_pos
        
        Logging.log "Component creation completed successfully: #{result.inspect}"
        return result
        
      rescue StandardError => e
        Logging.log "Error in create_component: #{e.message}"
        Logging.log e.backtrace.join("\n")
        raise
      end
    end

    def self.create_cube(entities, pos, dims, direction = "up", origin_mode = "center")
      Logging.log "Creating cube at position #{pos.inspect} with dimensions #{dims.inspect}, direction: #{direction}, origin_mode: #{origin_mode}"
      
      group = entities.add_group
      Logging.log "Created group: #{group.inspect}"
      
      # pos is now the CENTER position after origin_mode calculation
      # Calculate dimensions
      width, height, depth = dims
      half_width = width / 2.0
      half_height = height / 2.0  
      half_depth = depth / 2.0
      
      # Determine which face to create and which direction to extrude based on direction parameter
      case direction
      when "up"
        # Create base face at bottom, extrude upward
        base_z = pos[2] - half_depth
        extrude_distance = depth
        
        # Create base face with counter-clockwise vertex order (viewed from above)
        # This ensures the face normal points upward for positive pushpull
        face_vertices = [
          [pos[0] - half_width, pos[1] - half_height, base_z],     # bottom-left
          [pos[0] - half_width, pos[1] + half_height, base_z],     # top-left
          [pos[0] + half_width, pos[1] + half_height, base_z],     # top-right
          [pos[0] + half_width, pos[1] - half_height, base_z]      # bottom-right
        ]
        
      when "down"
        # Create top face, extrude downward
        base_z = pos[2] + half_depth
        extrude_distance = depth
        
        # Create face with clockwise vertex order (viewed from above)
        # This ensures the face normal points downward for positive pushpull
        face_vertices = [
          [pos[0] - half_width, pos[1] - half_height, base_z],     # bottom-left
          [pos[0] + half_width, pos[1] - half_height, base_z],     # bottom-right
          [pos[0] + half_width, pos[1] + half_height, base_z],     # top-right
          [pos[0] - half_width, pos[1] + half_height, base_z]      # top-left
        ]
        
      when "forward"
        # Create base face in XZ plane at back, extrude forward
        base_y = pos[1] - half_height
        extrude_distance = height
        
        # Create base face with vertices ordered for forward-pointing normal
        face_vertices = [
          [pos[0] - half_width, base_y, pos[2] - half_depth],     # bottom-left
          [pos[0] - half_width, base_y, pos[2] + half_depth],     # top-left
          [pos[0] + half_width, base_y, pos[2] + half_depth],     # top-right
          [pos[0] + half_width, base_y, pos[2] - half_depth]      # bottom-right
        ]
        
      when "back"
        # Create face in XZ plane at front, extrude backward
        base_y = pos[1] + half_height
        extrude_distance = height
        
        # Create base face with vertices ordered for backward-pointing normal
        face_vertices = [
          [pos[0] - half_width, base_y, pos[2] - half_depth],     # bottom-left
          [pos[0] + half_width, base_y, pos[2] - half_depth],     # bottom-right
          [pos[0] + half_width, base_y, pos[2] + half_depth],     # top-right
          [pos[0] - half_width, base_y, pos[2] + half_depth]      # top-left
        ]
        
      when "right"
        # Create base face in YZ plane at left, extrude rightward
        base_x = pos[0] - half_width
        extrude_distance = width
        
        # Create base face with vertices ordered for rightward-pointing normal
        face_vertices = [
          [base_x, pos[1] - half_height, pos[2] - half_depth],    # bottom-front
          [base_x, pos[1] + half_height, pos[2] - half_depth],    # bottom-back
          [base_x, pos[1] + half_height, pos[2] + half_depth],    # top-back
          [base_x, pos[1] - half_height, pos[2] + half_depth]     # top-front
        ]
        
      when "left"
        # Create base face in YZ plane at right, extrude leftward
        base_x = pos[0] + half_width
        extrude_distance = width
        
        # Create base face with vertices ordered for leftward-pointing normal
        face_vertices = [
          [base_x, pos[1] - half_height, pos[2] - half_depth],    # bottom-front
          [base_x, pos[1] - half_height, pos[2] + half_depth],    # top-front
          [base_x, pos[1] + half_height, pos[2] + half_depth],    # top-back
          [base_x, pos[1] + half_height, pos[2] - half_depth]     # bottom-back
        ]
        
      when "auto"
        # Auto defaults to "up"
        base_z = pos[2] - half_depth
        extrude_distance = depth
        
        face_vertices = [
          [pos[0] - half_width, pos[1] - half_height, base_z],     # bottom-left
          [pos[0] - half_width, pos[1] + half_height, base_z],     # top-left
          [pos[0] + half_width, pos[1] + half_height, base_z],     # top-right
          [pos[0] + half_width, pos[1] - half_height, base_z]      # bottom-right
        ]
        
      else
        raise "Unsupported direction: #{direction}"
      end
      
      Logging.log "Creating base face with vertices: #{face_vertices.inspect}"
      Logging.log "Will extrude by: #{extrude_distance} in direction: #{direction}"
      
      face = group.entities.add_face(face_vertices)
      Logging.log "Created face: #{face.inspect}"
      
      unless face
        raise "Failed to create base face for cube"
      end
      
      # Check face normal direction to ensure it matches our intention
      normal = face.normal
      Logging.log "Face normal: #{normal.inspect}"
      
      # For 'up' and 'auto' (which defaults to 'up'), ensure normal is pointing up (+Z)
      if (direction == "up" || direction == "auto") && normal.z < 0
        face.reverse!
        normal = face.normal # Re-fetch normal after reversal
        Logging.log "Reversed face normal for UP/AUTO direction. New normal: #{normal.inspect}"
      end
      
      # For 'down', ensure normal is pointing down (-Z)
      if direction == "down" && normal.z > 0
        face.reverse!
        normal = face.normal # Re-fetch normal after reversal
        Logging.log "Reversed face normal for DOWN direction. New normal: #{normal.inspect}"
      end
      
      # Similar checks can be added for other directions if they also prove problematic
      # e.g., for 'forward' (Y+), normal.y should be > 0
      # for 'back' (Y-), normal.y should be < 0
      # for 'right' (X+), normal.x should be > 0
      # for 'left' (X-), normal.x should be < 0

      # Extrude the face to create the cube
      begin
        pushpull_result = face.pushpull(extrude_distance)
        Logging.log "Pushpull operation completed with result: #{pushpull_result.inspect}"
      rescue StandardError => e
        raise "Failed to extrude cube face: #{e.message}. Extrude distance was: #{extrude_distance.inspect}"
      end
      Logging.log "Pushed/pulled face by #{extrude_distance} in direction #{direction}"
      
      result = { 
        id: group.entityID,
        success: true,
        type: "cube",
        direction: direction,
        origin_mode: origin_mode
      }
      Logging.log "Returning result: #{result.inspect}"
      result
    end

    def self.create_cylinder(entities, pos, dims, direction, origin_mode)
      Logging.log "Creating cylinder at position #{pos.inspect} with dimensions #{dims.inspect}"
      
      # Create a group to contain the cylinder
      group = entities.add_group
      Logging.log "Created group for cylinder: #{group.inspect}"
      
      # Extract dimensions with validation
      radius = dims[0] / 2.0
      height = dims[2]  # This is now guaranteed to exist and be valid
      
      Logging.log "Cylinder radius: #{radius}, height: #{height}"
      
      # Validate radius and height
      if radius <= 0
        raise "Invalid radius: #{radius}. Must be greater than 0."
      end
      if height <= 0
        raise "Invalid height: #{height}. Must be greater than 0."
      end
      
      # pos is the CENTER of the cylinder, so calculate the base center
      # The cylinder extends ±height/2 from the center in Z direction
      base_center = [pos[0], pos[1], pos[2] - height/2.0]
      Logging.log "Cylinder center: #{pos.inspect}, base center: #{base_center.inspect}"
      
      # Create points for a circle with validation
      num_segments = 24  # Number of segments for the circle
      circle_points = []
      
      begin
        # Create points in COUNTER-CLOCKWISE order (when viewed from above)
        # This ensures the face normal points UPWARD (+Z direction)
        num_segments.times do |i|
          angle = Math::PI * 2 * i / num_segments
          x = base_center[0] + radius * Math.cos(angle)
          y = base_center[1] + radius * Math.sin(angle)
          z = base_center[2]
          circle_points << [x, y, z]
        end
        
        # Reverse the points to get counter-clockwise winding for upward normal
        circle_points.reverse!
        
        Logging.log "Generated #{circle_points.length} circle points (counter-clockwise for upward normal)"
        
        # Validate that we have enough points
        if circle_points.length < 3
          raise "Not enough points to create a face: #{circle_points.length}"
        end
        
        # Create the circular face
        Logging.log "About to create circular face..."
        face = group.entities.add_face(circle_points)
        unless face
          raise "Failed to create base face for cylinder - add_face returned nil"
        end
        
        Logging.log "Created circular face: #{face.inspect}"
        
        # Check face normal direction to ensure it points upward
        normal = face.normal
        Logging.log "Face normal: #{normal.inspect}"
        
        # If the normal is pointing downward (negative Z), reverse the face
        if normal.z < 0
          face.reverse!
          normal = face.normal # Re-fetch normal after reversal
          Logging.log "Reversed face normal for upward direction. New normal: #{normal.inspect}"
        end
        
        # Validate height before pushpull
        unless height.is_a?(Numeric) && height > 0
          raise "Invalid height value for cylinder: #{height.inspect}. Must be a positive number."
        end
        
        # Extrude the face to create the cylinder
        Logging.log "About to pushpull face by #{height} in direction of normal #{normal.inspect}..."
        begin
          pushpull_result = face.pushpull(height)
          Logging.log "Pushpull operation completed with result: #{pushpull_result.inspect}"
        rescue StandardError => e
          raise "Failed to extrude cylinder face: #{e.message}. Height was: #{height.inspect}"
        end
        
        result = { 
          id: group.entityID,
          success: true,
          type: "cylinder",
          radius: radius,
          height: height
        }
        Logging.log "Created cylinder successfully, returning result: #{result.inspect}"
        result
        
      rescue StandardError => e
        Logging.log "Error creating cylinder geometry: #{e.message}"
        Logging.log "Cylinder error backtrace: #{e.backtrace.join("\n")}"
        
        # Clean up the group if geometry creation failed
        begin
          group.erase! if group && group.valid?
        rescue
          # Ignore cleanup errors
        end
        
        raise "Cylinder creation failed: #{e.message}"
      end
    end

    def self.create_sphere(entities, pos, dims, direction, origin_mode)
      Logging.log "Creating sphere at position #{pos.inspect} with dimensions #{dims.inspect}"
      
      # Create a group to contain the sphere
      group = entities.add_group
      
      # Extract dimensions - pos is already the CENTER of the sphere
      radius = dims[0] / 2.0
      center = pos  # pos is the center, no adjustment needed
      Logging.log "Sphere center: #{center.inspect}, radius: #{radius}"
      
      # Create a UV sphere with latitude and longitude segments
      segments = 16
      
      # Create points for the sphere
      points = []
      for lat_i in 0..segments
        lat = Math::PI * lat_i / segments
        for lon_i in 0..segments
          lon = 2 * Math::PI * lon_i / segments
          x = center[0] + radius * Math.sin(lat) * Math.cos(lon)
          y = center[1] + radius * Math.sin(lat) * Math.sin(lon)
          z = center[2] + radius * Math.cos(lat)
          points << [x, y, z]
        end
      end
      
      # Create faces for the sphere (simplified approach)
      faces_created = 0
      for lat_i in 0...segments
        for lon_i in 0...segments
          i1 = lat_i * (segments + 1) + lon_i
          i2 = i1 + 1
          i3 = i1 + segments + 1
          i4 = i3 + 1
          
          # Create a quad face
          begin
            face = group.entities.add_face(points[i1], points[i2], points[i4], points[i3])
            faces_created += 1 if face
          rescue StandardError => e
            # Skip faces that can't be created (may happen at poles)
            Logging.log "Skipping face: #{e.message}"
          end
        end
      end
      
      Logging.log "Created #{faces_created} faces for sphere"
      
      result = { 
        id: group.entityID,
        success: true
      }
      Logging.log "Created sphere, returning result: #{result.inspect}"
      result
    end

    def self.create_cone(entities, pos, dims, direction, origin_mode)
      Logging.log "Creating cone at position #{pos.inspect} with dimensions #{dims.inspect}"
      
      # Create a group to contain the cone
      group = entities.add_group
      
      # Extract dimensions - pos is the CENTER of the cone's base
      radius = dims[0] / 2.0
      height = dims[2]
      
      # pos is the center of the base, so use it directly
      base_center = pos
      apex = [base_center[0], base_center[1], base_center[2] + height]
      Logging.log "Cone base center: #{base_center.inspect}, apex: #{apex.inspect}, radius: #{radius}"
      
      # Create points for a circle
      num_segments = 24  # Number of segments for the circle
      circle_points = []
      
      num_segments.times do |i|
        angle = Math::PI * 2 * i / num_segments
        x = base_center[0] + radius * Math.cos(angle)
        y = base_center[1] + radius * Math.sin(angle)
        z = base_center[2]
        circle_points << [x, y, z]
      end
      
      # Create the circular face for the base
      base = group.entities.add_face(circle_points)
      unless base
        raise "Failed to create base face for cone"
      end
      
      # Create the cone sides
      (0...num_segments).each do |i|
        j = (i + 1) % num_segments
        # Create a triangular face from two adjacent points on the circle to the apex
        group.entities.add_face(circle_points[i], circle_points[j], apex)
      end
      
      result = { 
        id: group.entityID,
        success: true
      }
      Logging.log "Created cone, returning result: #{result.inspect}"
      result
    end

    def self.delete_component(params)
      model = Sketchup.active_model
      
      # Handle ID format - strip quotes if present
      id_str = params["id"].to_s.gsub('"', '')
      Logging.log "Looking for entity with ID: #{id_str}"
      
      entity = model.find_entity_by_id(id_str.to_i)
      
      if entity
        Logging.log "Found entity: #{entity.inspect}"
        entity.erase!
        { success: true }
      else
        raise "Entity not found"
      end
    end

    def self.transform_component(params)
      model = Sketchup.active_model
      
      # Handle ID format - strip quotes if present
      id_str = params["id"].to_s.gsub('"', '')
      Logging.log "Looking for entity with ID: #{id_str}"
      
      entity = model.find_entity_by_id(id_str.to_i)
      
      if entity
        Logging.log "Found entity: #{entity.inspect}"
        
        # Handle position
        if params["position"]
          target_pos = params["position"]
          Logging.log "Transforming to absolute position #{target_pos.inspect}"
          
          # Get current center position
          current_bounds = entity.bounds
          current_center = current_bounds.center
          current_pos = [current_center.x.to_f, current_center.y.to_f, current_center.z.to_f]
          
          Logging.log "Current center position: #{current_pos.inspect}"
          
          # Calculate the movement needed to reach target position
          movement = [
            target_pos[0] - current_pos[0],
            target_pos[1] - current_pos[1], 
            target_pos[2] - current_pos[2]
          ]
          
          Logging.log "Movement vector: #{movement.inspect}"
          
          # Create a transformation to move the entity
          translation = Geom::Transformation.translation(Geom::Vector3d.new(movement[0], movement[1], movement[2]))
          entity.transform!(translation)
          
          # Verify the final position
          final_bounds = entity.bounds
          final_center = final_bounds.center
          final_pos = [final_center.x.to_f, final_center.y.to_f, final_center.z.to_f]
          Logging.log "Final center position: #{final_pos.inspect}"
        end
        
        # Handle rotation (in degrees)
        if params["rotation"]
          rot = params["rotation"]
          Logging.log "Rotating by #{rot.inspect} degrees"
          
          # Convert to radians
          x_rot = rot[0] * Math::PI / 180
          y_rot = rot[1] * Math::PI / 180
          z_rot = rot[2] * Math::PI / 180
          
          # Apply rotations
          if rot[0] != 0
            rotation = Geom::Transformation.rotation(entity.bounds.center, Geom::Vector3d.new(1, 0, 0), x_rot)
            entity.transform!(rotation)
          end
          
          if rot[1] != 0
            rotation = Geom::Transformation.rotation(entity.bounds.center, Geom::Vector3d.new(0, 1, 0), y_rot)
            entity.transform!(rotation)
          end
          
          if rot[2] != 0
            rotation = Geom::Transformation.rotation(entity.bounds.center, Geom::Vector3d.new(0, 0, 1), z_rot)
            entity.transform!(rotation)
          end
        end
        
        # Handle scale
        if params["scale"]
          scale = params["scale"]
          Logging.log "Scaling by #{scale.inspect}"
          
          # Create a transformation to scale the entity
          center = entity.bounds.center
          scaling = Geom::Transformation.scaling(center, scale[0], scale[1], scale[2])
          entity.transform!(scaling)
        end
        
        { success: true, id: entity.entityID }
      else
        raise "Entity not found"
      end
    end

    def self.get_selection
      model = Sketchup.active_model
      selection = model.selection
      
      selected_entities = selection.map do |entity|
        {
          id: entity.entityID,
          type: entity.class.name,
          bounds: entity.bounds ? {
            min: [entity.bounds.min.x, entity.bounds.min.y, entity.bounds.min.z],
            max: [entity.bounds.max.x, entity.bounds.max.y, entity.bounds.max.z]
          } : nil
        }
      end
      
      {
        success: true,
        count: selection.length,
        entities: selected_entities
      }
    end
  end
end 