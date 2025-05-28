module SketchupMCP
  module MeasurementTools
    def self.calculate_distance(params)
      Logging.log "Calculating distance with params: #{params.inspect}"
      
      point1 = params["point1"]
      point2 = params["point2"]
      
      # Validate input parameters
      unless point1 && point1.is_a?(Array) && point1.length == 3
        raise "Invalid point1: #{point1.inspect}. Must be an array of 3 numbers [x, y, z]"
      end
      
      unless point2 && point2.is_a?(Array) && point2.length == 3
        raise "Invalid point2: #{point2.inspect}. Must be an array of 3 numbers [x, y, z]"
      end
      
      # Ensure all coordinates are numeric
      point1 = point1.map { |coord| coord.to_f }
      point2 = point2.map { |coord| coord.to_f }
      
      # Calculate distance using 3D distance formula
      dx = point2[0] - point1[0]
      dy = point2[1] - point1[1]
      dz = point2[2] - point1[2]
      
      distance = Math.sqrt(dx*dx + dy*dy + dz*dz)
      
      result = {
        distance: distance,
        point1: point1,
        point2: point2,
        delta: [dx, dy, dz],
        success: true
      }
      
      Logging.log "Distance calculation result: #{result.inspect}"
      result
    end

    def self.measure_components(params)
      Logging.log "Measuring components with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      component_ids = params["component_ids"]
      measure_type = params["type"] || "center_to_center"
      
      unless component_ids && component_ids.is_a?(Array) && component_ids.length >= 2
        raise "Invalid component_ids: #{component_ids.inspect}. Must be an array with at least 2 component IDs"
      end
      
      # Find the components in the model
      components = []
      all_entities = []
      
      # Collect all entities from all contexts
      collect_all_entities(model.entities, all_entities)
      
      component_ids.each do |id|
        entity = all_entities.find { |e| e.entityID == id }
        unless entity
          raise "Component with ID #{id} not found in model"
        end
        components << entity
      end
      
      measurements = []
      
      # Measure distance between each pair of components
      for i in 0...(components.length - 1)
        for j in (i + 1)...components.length
          comp1 = components[i]
          comp2 = components[j]
          
          case measure_type
          when "center_to_center"
            point1 = get_component_center(comp1)
            point2 = get_component_center(comp2)
          when "bounds_to_bounds"
            point1, point2 = get_closest_bounds_points(comp1, comp2)
          when "origin_to_origin"
            point1 = get_component_origin(comp1)
            point2 = get_component_origin(comp2)
          else
            raise "Unknown measurement type: #{measure_type}"
          end
          
          distance = calculate_distance_between_points(point1, point2)
          
          measurements << {
            component1_id: comp1.entityID,
            component2_id: comp2.entityID,
            point1: point1,
            point2: point2,
            distance: distance,
            measurement_type: measure_type
          }
        end
      end
      
      result = {
        measurements: measurements,
        component_count: components.length,
        measurement_type: measure_type,
        success: true
      }
      
      Logging.log "Component measurement result: #{result.inspect}"
      result
    end

    def self.inspect_component(params)
      Logging.log "Inspecting component with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      component_id = params["component_id"]
      unless component_id
        raise "Missing component_id parameter"
      end
      
      # Find the component in the model
      all_entities = []
      collect_all_entities(model.entities, all_entities)
      
      component = all_entities.find { |e| e.entityID == component_id }
      unless component
        raise "Component with ID #{component_id} not found in model"
      end
      
      # Get component information
      bounds = component.bounds
      center = get_component_center(component)
      origin = get_component_origin(component)
      
      # Get transformation if it's a group or component instance
      transformation = nil
      if component.respond_to?(:transformation)
        transformation = component.transformation
      end
      
      # Get dimensions
      width = bounds.width.to_f
      height = bounds.height.to_f
      depth = bounds.depth.to_f
      
      # Get corner points
      corners = get_bounds_corners(bounds)
      
      result = {
        component_id: component_id,
        type: component.class.name,
        bounds: {
          min: [bounds.min.x.to_f, bounds.min.y.to_f, bounds.min.z.to_f],
          max: [bounds.max.x.to_f, bounds.max.y.to_f, bounds.max.z.to_f],
          center: center,
          width: width,
          height: height,
          depth: depth,
          corners: corners
        },
        origin: origin,
        transformation: transformation ? transformation.to_a : nil,
        entity_info: {
          valid: component.valid?,
          deleted: component.deleted?,
          visible: component.visible?,
          layer: component.layer ? component.layer.name : nil
        },
        success: true
      }
      
      Logging.log "Component inspection result: #{result.inspect}"
      result
    end

    def self.create_reference_markers(params)
      Logging.log "Creating reference markers with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      points = params["points"]
      size = params["size"] || 1.0
      color = params["color"] || "red"
      label_prefix = params["label_prefix"] || "REF"
      
      unless points && points.is_a?(Array) && !points.empty?
        raise "Invalid points: #{points.inspect}. Must be an array of point coordinates"
      end
      
      # Validate size
      size = size.to_f
      if size <= 0
        raise "Invalid size: #{size}. Must be greater than 0"
      end
      
      markers = []
      entities = model.active_entities
      
      points.each_with_index do |point, index|
        unless point && point.is_a?(Array) && point.length == 3
          raise "Invalid point at index #{index}: #{point.inspect}. Must be an array of 3 numbers [x, y, z]"
        end
        
        # Normalize point coordinates
        pos = point.map { |coord| coord.to_f }
        
        # Create a small cube marker
        group = entities.add_group
        
        # Create cube geometry
        half_size = size / 2.0
        face = group.entities.add_face(
          [pos[0] - half_size, pos[1] - half_size, pos[2] - half_size],
          [pos[0] + half_size, pos[1] - half_size, pos[2] - half_size],
          [pos[0] + half_size, pos[1] + half_size, pos[2] - half_size],
          [pos[0] - half_size, pos[1] + half_size, pos[2] - half_size]
        )
        
        face.pushpull(size)
        
        # Set color if specified
        if color && color != "default"
          material = set_marker_material(group, color)
        end
        
        # Add text label
        label = "#{label_prefix}_#{index + 1}"
        text_point = [pos[0], pos[1], pos[2] + size]
        text = entities.add_text(label, text_point)
        
        marker_info = {
          id: group.entityID,
          label: label,
          position: pos,
          size: size,
          color: color,
          text_id: text.entityID
        }
        
        markers << marker_info
        
        Logging.log "Created reference marker #{label} at #{pos.inspect}"
      end
      
      result = {
        markers: markers,
        marker_count: markers.length,
        success: true
      }
      
      Logging.log "Reference markers creation result: #{result.inspect}"
      result
    end

    def self.clear_reference_markers(params = {})
      Logging.log "Clearing reference markers with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      label_prefix = params["label_prefix"] || "REF"
      
      entities = model.active_entities
      removed_count = 0
      
      # Find and remove all text entities with matching prefix
      texts_to_remove = []
      entities.grep(Sketchup::Text) do |text|
        if text.text.start_with?(label_prefix)
          texts_to_remove << text
        end
      end
      
      # Find groups that might be reference markers (small cubes near text labels)
      groups_to_remove = []
      texts_to_remove.each do |text|
        text_pos = text.point
        entities.grep(Sketchup::Group) do |group|
          group_center = get_component_center(group)
          distance = calculate_distance_between_points(
            [text_pos.x, text_pos.y, text_pos.z], 
            group_center
          )
          # If group is close to text (within 5 units), consider it a marker
          if distance < 5.0
            groups_to_remove << group
          end
        end
      end
      
      # Remove the markers
      (texts_to_remove + groups_to_remove).each do |entity|
        begin
          entity.erase!
          removed_count += 1
        rescue => e
          Logging.log "Warning: Failed to remove entity #{entity.entityID}: #{e.message}"
        end
      end
      
      result = {
        removed_count: removed_count,
        label_prefix: label_prefix,
        success: true
      }
      
      Logging.log "Reference markers cleanup result: #{result.inspect}"
      result
    end

    def self.snap_align_component(params)
      Logging.log "Snapping/aligning component with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      source_id = params["source_component_id"]
      target_id = params["target_component_id"]
      alignment_type = params["alignment_type"] || "center_to_center"
      offset = params["offset"] || [0, 0, 0]
      
      unless source_id
        raise "Missing source_component_id parameter"
      end
      
      unless target_id
        raise "Missing target_component_id parameter"
      end
      
      # Find components
      all_entities = []
      collect_all_entities(model.entities, all_entities)
      
      source_comp = all_entities.find { |e| e.entityID == source_id }
      target_comp = all_entities.find { |e| e.entityID == target_id }
      
      unless source_comp
        raise "Source component with ID #{source_id} not found"
      end
      
      unless target_comp
        raise "Target component with ID #{target_id} not found"
      end
      
      # Calculate target position based on alignment type
      target_position = case alignment_type
      when "center_to_center"
        get_component_center(target_comp)
      when "origin_to_origin"
        get_component_origin(target_comp)
      when "bounds_min_to_min"
        bounds = target_comp.bounds
        [bounds.min.x, bounds.min.y, bounds.min.z]
      when "bounds_max_to_max"
        bounds = target_comp.bounds
        [bounds.max.x, bounds.max.y, bounds.max.z]
      when "top_surface"
        bounds = target_comp.bounds
        [bounds.center.x, bounds.center.y, bounds.max.z]
      when "bottom_surface"
        bounds = target_comp.bounds
        [bounds.center.x, bounds.center.y, bounds.min.z]
      else
        raise "Unknown alignment type: #{alignment_type}"
      end
      
      # Apply offset
      final_position = [
        target_position[0] + offset[0],
        target_position[1] + offset[1],
        target_position[2] + offset[2]
      ]
      
      # Get current source position for movement calculation
      current_position = case alignment_type
      when "center_to_center"
        get_component_center(source_comp)
      when "origin_to_origin"
        get_component_origin(source_comp)
      when "bounds_min_to_min"
        bounds = source_comp.bounds
        [bounds.min.x, bounds.min.y, bounds.min.z]
      when "bounds_max_to_max"
        bounds = source_comp.bounds
        [bounds.max.x, bounds.max.y, bounds.max.z]
      when "top_surface"
        bounds = source_comp.bounds
        [bounds.center.x, bounds.center.y, bounds.max.z]
      when "bottom_surface"
        bounds = source_comp.bounds
        [bounds.center.x, bounds.center.y, bounds.min.z]
      end
      
      # Calculate movement vector
      movement = [
        final_position[0] - current_position[0],
        final_position[1] - current_position[1],
        final_position[2] - current_position[2]
      ]
      
      # Apply transformation
      if source_comp.respond_to?(:transformation=)
        current_transform = source_comp.transformation
        translation = Geom::Transformation.translation(movement)
        new_transform = translation * current_transform
        source_comp.transformation = new_transform
      else
        # For entities that don't have transformation, we need to move all their geometry
        move_vector = Geom::Vector3d.new(movement[0], movement[1], movement[2])
        source_comp.entities.transform_entities(Geom::Transformation.translation(move_vector), source_comp.entities.to_a)
      end
      
      # Verify final position
      final_actual_position = get_component_center(source_comp)
      
      result = {
        source_component_id: source_id,
        target_component_id: target_id,
        alignment_type: alignment_type,
        offset: offset,
        movement_applied: movement,
        final_position: final_actual_position,
        success: true
      }
      
      Logging.log "Snap/align result: #{result.inspect}"
      result
    end

    def self.create_grid_system(params)
      Logging.log "Creating grid system with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      origin = params["origin"] || [0, 0, 0]
      x_spacing = params["x_spacing"] || 10.0
      y_spacing = params["y_spacing"] || 10.0
      x_count = params["x_count"] || 10
      y_count = params["y_count"] || 10
      marker_size = params["marker_size"] || 0.5
      show_labels = params["show_labels"] != false  # Default true
      color = params["color"] || "gray"
      label_prefix = params["label_prefix"] || "GRID"
      
      grid_points = []
      created_markers = []
      entities = model.active_entities
      
      # Create grid points
      for x in 0..x_count
        for y in 0..y_count
          point = [
            origin[0] + (x * x_spacing),
            origin[1] + (y * y_spacing),
            origin[2]
          ]
          grid_points << point
          
          # Create marker
          group = entities.add_group
          
          # Create small cube marker
          half_size = marker_size / 2.0
          face = group.entities.add_face(
            [point[0] - half_size, point[1] - half_size, point[2] - half_size],
            [point[0] + half_size, point[1] - half_size, point[2] - half_size],
            [point[0] + half_size, point[1] + half_size, point[2] - half_size],
            [point[0] - half_size, point[1] + half_size, point[2] - half_size]
          )
          
          face.pushpull(marker_size)
          
          # Set color
          if color && color != "default"
            set_marker_material(group, color)
          end
          
          marker_info = {
            id: group.entityID,
            position: point,
            grid_x: x,
            grid_y: y
          }
          
          # Add label if requested
          if show_labels
            label = "#{label_prefix}_#{x}_#{y}"
            text_point = [point[0], point[1], point[2] + marker_size]
            text = entities.add_text(label, text_point)
            marker_info[:label] = label
            marker_info[:text_id] = text.entityID
          end
          
          created_markers << marker_info
        end
      end
      
      result = {
        grid_origin: origin,
        x_spacing: x_spacing,
        y_spacing: y_spacing,
        x_count: x_count,
        y_count: y_count,
        total_markers: created_markers.length,
        markers: created_markers,
        success: true
      }
      
      Logging.log "Grid system creation result: #{result.inspect}"
      result
    end

    def self.query_all_components(params = {})
      Logging.log "Querying all components with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      include_details = params["include_details"] != false  # Default true
      component_type_filter = params["type_filter"]  # Optional filter by type
      
      all_entities = []
      collect_all_entities(model.entities, all_entities)
      
      components = []
      
      all_entities.each do |entity|
        # Skip non-component entities unless requested
        next unless entity.is_a?(Sketchup::Group) || 
                   entity.is_a?(Sketchup::ComponentInstance) ||
                   entity.is_a?(Sketchup::Face) ||
                   entity.is_a?(Sketchup::Edge)
        
        # Apply type filter if specified
        if component_type_filter
          next unless entity.class.name.downcase.include?(component_type_filter.downcase)
        end
        
        component_info = {
          id: entity.entityID,
          type: entity.class.name
        }
        
        if include_details
          # Get position information
          if entity.respond_to?(:bounds)
            bounds = entity.bounds
            component_info[:bounds] = {
              min: [bounds.min.x.to_f, bounds.min.y.to_f, bounds.min.z.to_f],
              max: [bounds.max.x.to_f, bounds.max.y.to_f, bounds.max.z.to_f],
              center: get_component_center(entity),
              width: bounds.width,
              height: bounds.height,
              depth: bounds.depth
            }
          end
          
          # Get origin/transformation
          if entity.respond_to?(:transformation)
            origin = entity.transformation.origin
            component_info[:origin] = [origin.x, origin.y, origin.z]
            component_info[:transformation] = entity.transformation.to_a
          end
          
          # Get entity properties
          component_info[:properties] = {
            valid: entity.valid?,
            visible: entity.visible?,
            layer: entity.layer ? entity.layer.name : nil
          }
          
          # Get material if applicable
          if entity.respond_to?(:material) && entity.material
            component_info[:material] = entity.material.name
          end
          
          # Get definition name for component instances
          if entity.respond_to?(:definition) && entity.definition
            component_info[:definition_name] = entity.definition.name
          end
        end
        
        components << component_info
      end
      
      result = {
        total_components: components.length,
        components: components,
        success: true
      }
      
      if component_type_filter
        result[:filtered_by_type] = component_type_filter
      end
      
      Logging.log "Component query result: found #{components.length} components"
      result
    end

    def self.position_relative_to_component(params)
      Logging.log "Positioning component relative to another with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      source_id = params["source_component_id"]
      reference_id = params["reference_component_id"]
      relative_position = params["relative_position"]
      offset = params["offset"] || [0, 0, 0]
      
      unless source_id
        raise "Missing source_component_id parameter"
      end
      
      unless reference_id
        raise "Missing reference_component_id parameter"
      end
      
      unless relative_position
        raise "Missing relative_position parameter (e.g., 'above', 'below', 'left', 'right', 'front', 'back', 'center')"
      end
      
      # Find components
      all_entities = []
      collect_all_entities(model.entities, all_entities)
      
      source_comp = all_entities.find { |e| e.entityID == source_id }
      reference_comp = all_entities.find { |e| e.entityID == reference_id }
      
      unless source_comp
        raise "Source component with ID #{source_id} not found"
      end
      
      unless reference_comp
        raise "Reference component with ID #{reference_id} not found"
      end
      
      # Get reference component info
      ref_bounds = reference_comp.bounds
      ref_center = get_component_center(reference_comp)
      
      # Calculate target position based on relative position
      target_position = case relative_position.downcase
      when "above", "top"
        [ref_center[0], ref_center[1], ref_bounds.max.z]
      when "below", "bottom"
        [ref_center[0], ref_center[1], ref_bounds.min.z]
      when "left", "west"
        [ref_bounds.min.x, ref_center[1], ref_center[2]]
      when "right", "east"
        [ref_bounds.max.x, ref_center[1], ref_center[2]]
      when "front", "south"
        [ref_center[0], ref_bounds.min.y, ref_center[2]]
      when "back", "north"
        [ref_center[0], ref_bounds.max.y, ref_center[2]]
      when "center"
        ref_center
      else
        raise "Unknown relative position: #{relative_position}. Use: above, below, left, right, front, back, center"
      end
      
      # Apply offset
      final_position = [
        target_position[0] + offset[0],
        target_position[1] + offset[1],
        target_position[2] + offset[2]
      ]
      
      # Move source component
      source_center = get_component_center(source_comp)
      movement = [
        final_position[0] - source_center[0],
        final_position[1] - source_center[1],
        final_position[2] - source_center[2]
      ]
      
      # Apply transformation
      if source_comp.respond_to?(:transformation=)
        current_transform = source_comp.transformation
        translation = Geom::Transformation.translation(movement)
        new_transform = translation * current_transform
        source_comp.transformation = new_transform
      else
        move_vector = Geom::Vector3d.new(movement[0], movement[1], movement[2])
        source_comp.entities.transform_entities(Geom::Transformation.translation(move_vector), source_comp.entities.to_a)
      end
      
      # Verify final position
      final_actual_position = get_component_center(source_comp)
      
      result = {
        source_component_id: source_id,
        reference_component_id: reference_id,
        relative_position: relative_position,
        offset: offset,
        calculated_target: final_position,
        movement_applied: movement,
        final_position: final_actual_position,
        success: true
      }
      
      Logging.log "Relative positioning result: #{result.inspect}"
      result
    end

    def self.position_between_components(params)
      Logging.log "Positioning component between others with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      source_id = params["source_component_id"]
      component1_id = params["component1_id"]
      component2_id = params["component2_id"]
      ratio = params["ratio"] || 0.5  # 0.5 = center, 0.0 = at component1, 1.0 = at component2
      offset = params["offset"] || [0, 0, 0]
      
      unless source_id && component1_id && component2_id
        raise "Missing required component IDs"
      end
      
      # Find components
      all_entities = []
      collect_all_entities(model.entities, all_entities)
      
      source_comp = all_entities.find { |e| e.entityID == source_id }
      comp1 = all_entities.find { |e| e.entityID == component1_id }
      comp2 = all_entities.find { |e| e.entityID == component2_id }
      
      unless source_comp && comp1 && comp2
        raise "One or more components not found"
      end
      
      # Get positions
      pos1 = get_component_center(comp1)
      pos2 = get_component_center(comp2)
      
      # Calculate interpolated position
      target_position = [
        pos1[0] + ratio * (pos2[0] - pos1[0]) + offset[0],
        pos1[1] + ratio * (pos2[1] - pos1[1]) + offset[1],
        pos1[2] + ratio * (pos2[2] - pos1[2]) + offset[2]
      ]
      
      # Move source component
      source_center = get_component_center(source_comp)
      movement = [
        target_position[0] - source_center[0],
        target_position[1] - source_center[1],
        target_position[2] - source_center[2]
      ]
      
      # Apply transformation
      if source_comp.respond_to?(:transformation=)
        current_transform = source_comp.transformation
        translation = Geom::Transformation.translation(movement)
        new_transform = translation * current_transform
        source_comp.transformation = new_transform
      else
        move_vector = Geom::Vector3d.new(movement[0], movement[1], movement[2])
        source_comp.entities.transform_entities(Geom::Transformation.translation(move_vector), source_comp.entities.to_a)
      end
      
      final_actual_position = get_component_center(source_comp)
      
      result = {
        source_component_id: source_id,
        component1_id: component1_id,
        component2_id: component2_id,
        ratio: ratio,
        offset: offset,
        component1_position: pos1,
        component2_position: pos2,
        calculated_target: target_position,
        movement_applied: movement,
        final_position: final_actual_position,
        success: true
      }
      
      Logging.log "Position between components result: #{result.inspect}"
      result
    end

    def self.show_component_bounds(params)
      Logging.log "Showing component bounds with params: #{params.inspect}"
      
      model = Sketchup.active_model
      unless model
        raise "No active SketchUp model available"
      end
      
      component_ids = params["component_ids"]
      show_wireframe = params["show_wireframe"] != false  # Default true
      color = params["color"] || "yellow"
      label_prefix = params["label_prefix"] || "BOUNDS"
      
      unless component_ids && component_ids.is_a?(Array) && !component_ids.empty?
        raise "Invalid component_ids: must be an array of component IDs"
      end
      
      all_entities = []
      collect_all_entities(model.entities, all_entities)
      
      bounds_info = []
      entities = model.active_entities
      
      component_ids.each_with_index do |component_id, index|
        component = all_entities.find { |e| e.entityID == component_id }
        unless component
          raise "Component with ID #{component_id} not found"
        end
        
        bounds = component.bounds
        corners = get_bounds_corners(bounds)
        
        # Create wireframe if requested
        wireframe_lines = []
        if show_wireframe
          # Create edges for the bounding box
          group = entities.add_group
          
          # Bottom face
          bottom_face = [
            corners[0], corners[1], corners[4], corners[2], corners[0]
          ]
          group.entities.add_edges(bottom_face)
          
          # Top face  
          top_face = [
            corners[3], corners[5], corners[7], corners[6], corners[3]
          ]
          group.entities.add_edges(top_face)
          
          # Vertical edges
          [[corners[0], corners[3]], [corners[1], corners[5]], 
           [corners[2], corners[6]], [corners[4], corners[7]]].each do |edge_points|
            group.entities.add_line(edge_points[0], edge_points[1])
          end
          
          # Set material
          if color && color != "default"
            set_marker_material(group, color)
          end
          
          wireframe_lines << group.entityID
        end
        
        # Add label
        label = "#{label_prefix}_#{index + 1}"
        center = [(bounds.min.x + bounds.max.x) / 2, 
                 (bounds.min.y + bounds.max.y) / 2, 
                 bounds.max.z + 1]
        text = entities.add_text(label, center)
        
        bounds_data = {
          component_id: component_id,
          bounds: {
            min: [bounds.min.x.to_f, bounds.min.y.to_f, bounds.min.z.to_f],
            max: [bounds.max.x.to_f, bounds.max.y.to_f, bounds.max.z.to_f],
            center: [bounds.center.x, bounds.center.y, bounds.center.z],
            width: bounds.width,
            height: bounds.height,
            depth: bounds.depth,
            corners: corners
          },
          wireframe_ids: wireframe_lines,
          label: label,
          text_id: text.entityID
        }
        
        bounds_info << bounds_data
      end
      
      result = {
        component_count: component_ids.length,
        bounds_info: bounds_info,
        show_wireframe: show_wireframe,
        success: true
      }
      
      Logging.log "Component bounds visualization result: #{result.inspect}"
      result
    end

    def self.create_component_with_verification(params)
      Logging.log "Creating component with verification, params: #{params.inspect}"
      
      # Create the component using the standard method
      result = SketchupMCP::ComponentTools.create_component(params)
      
      # Enhance with verification data
      if result[:success] && result[:id]
        verification = inspect_component({"component_id" => result[:id]})
        result[:verification] = verification
        
        # Add enhanced positioning accuracy and explanation
        accuracy = calculate_positioning_accuracy(params, verification)
        result[:positioning_accuracy] = accuracy
        
        # Extract directional parameters for enhanced explanation
        direction = params["direction"] || "up"
        origin_mode = params["origin_mode"] || "center"
        requested_pos = params["position"] || [0, 0, 0]
        actual_center = verification[:bounds][:center]
        requested_dims = params["dimensions"] || [1, 1, 1]
        actual_dims = [verification[:bounds][:width], verification[:bounds][:height], verification[:bounds][:depth]]
        
        # Calculate expected bounds based on origin_mode and direction
        if origin_mode == "center"
          # Original center-based calculation
          half_width = requested_dims[0] / 2.0
          half_depth = requested_dims[1] / 2.0
          half_height = requested_dims[2] / 2.0
          
          expected_center = requested_pos
          expected_min = [
            expected_center[0] - half_width,
            expected_center[1] - half_depth, 
            expected_center[2] - half_height
          ]
          expected_max = [
            expected_center[0] + half_width,
            expected_center[1] + half_depth,
            expected_center[2] + half_height
          ]
        else
          # Use validation helper to calculate expected center and bounds
          calculated_center = SketchupMCP::Validation.calculate_origin_position(requested_pos, requested_dims, origin_mode)
          half_width = requested_dims[0] / 2.0
          half_depth = requested_dims[1] / 2.0
          half_height = requested_dims[2] / 2.0
          
          expected_center = calculated_center
          expected_min = [
            calculated_center[0] - half_width,
            calculated_center[1] - half_depth, 
            calculated_center[2] - half_height
          ]
          expected_max = [
            calculated_center[0] + half_width,
            calculated_center[1] + half_depth,
            calculated_center[2] + half_height
          ]
        end
        
        # Enhanced positioning explanation with directional information
        origin_explanation = case origin_mode
        when "center"
          "CENTER POINT"
        when "bottom_center"
          "BOTTOM-CENTER POINT (component extends upward from this point)"
        when "top_center"
          "TOP-CENTER POINT (component extends downward from this point)"
        when "min_corner"
          "MINIMUM CORNER (x_min, y_min, z_min)"
        when "max_corner"
          "MAXIMUM CORNER (x_max, y_max, z_max)"
        else
          "CENTER POINT (default)"
        end
        
        direction_explanation = case direction
        when "up"
          "Component created by extruding upward in +Z direction."
        when "down"
          "Component created by extruding downward in -Z direction."
        when "forward"
          "Component created by extruding forward in +Y direction."
        when "back"
          "Component created by extruding backward in -Y direction."
        when "right"
          "Component created by extruding rightward in +X direction."
        when "left"
          "Component created by extruding leftward in -X direction."
        when "auto"
          "Component created using automatic direction (upward)."
        else
          "Component created with standard upward extrusion."
        end
        
        result[:positioning_explanation] = "Requested position #{requested_pos} was interpreted as #{origin_explanation}. #{direction_explanation} Component center placed at #{actual_center}. Expected bounds: #{expected_min} to #{expected_max}. Actual bounds: #{verification[:bounds][:min]} to #{verification[:bounds][:max]}. Positioning accuracy: #{accuracy[:error_distance].round(3)} units from requested center position."
        
        result[:dimension_verification] = {
          requested: requested_dims,
          actual: actual_dims,
          match: (requested_dims.map(&:to_f) - actual_dims.map(&:to_f)).map(&:abs).all? { |diff| diff < 0.001 }
        }
        
        # Add directional metadata to result
        result[:directional_info] = {
          direction: direction,
          origin_mode: origin_mode,
          requested_position: requested_pos,
          calculated_center: expected_center,
          direction_explanation: direction_explanation,
          origin_explanation: origin_explanation
        }
        
        result[:created_at] = Time.now.to_f
      end
      
      result
    end

    def self.preview_position(params)
      Logging.log "Previewing position with params: #{params.inspect}"
      
      type = params["type"] || "cube"
      position = params["position"] || [0, 0, 0]
      dimensions = params["dimensions"] || [1, 1, 1]
      direction = params["direction"] || "up"
      origin_mode = params["origin_mode"] || "center"
      
      # Validate input parameters
      unless position && position.is_a?(Array) && position.length == 3
        raise "Invalid position: #{position.inspect}. Must be an array of 3 numbers [x, y, z]"
      end
      
      unless dimensions && dimensions.is_a?(Array) && dimensions.length == 3
        raise "Invalid dimensions: #{dimensions.inspect}. Must be an array of 3 numbers [width, height, depth]"
      end
      
      # Convert to numeric values
      requested_x, requested_y, requested_z = position.map(&:to_f)
      width, height, depth = dimensions.map(&:to_f)
      
      # Calculate actual center position based on origin_mode
      center_position = SketchupMCP::Validation.calculate_origin_position([requested_x, requested_y, requested_z], [width, height, depth], origin_mode)
      center_x, center_y, center_z = center_position
      
      # Calculate bounds based on center position
      # Component grows equally in all directions from center
      half_width = width / 2.0
      half_height = height / 2.0
      half_depth = depth / 2.0
      
      min_point = [center_x - half_width, center_y - half_height, center_z - half_depth]
      max_point = [center_x + half_width, center_y + half_height, center_z + half_depth]
      
      # Calculate all 8 corner points
      corners = [
        [min_point[0], min_point[1], min_point[2]], # min corner
        [max_point[0], min_point[1], min_point[2]], # +X
        [min_point[0], max_point[1], min_point[2]], # +Y  
        [max_point[0], max_point[1], min_point[2]], # +X+Y
        [min_point[0], min_point[1], max_point[2]], # +Z
        [max_point[0], min_point[1], max_point[2]], # +X+Z
        [min_point[0], max_point[1], max_point[2]], # +Y+Z
        [max_point[0], max_point[1], max_point[2]]  # max corner
      ]
      
      # Create enhanced positioning explanation
      origin_explanation = case origin_mode
      when "center"
        "CENTER POINT"
      when "bottom_center"
        "BOTTOM-CENTER POINT (component extends upward from this point)"
      when "top_center"
        "TOP-CENTER POINT (component extends downward from this point)"
      when "min_corner"
        "MINIMUM CORNER (x_min, y_min, z_min)"
      when "max_corner"
        "MAXIMUM CORNER (x_max, y_max, z_max)"
      else
        "CENTER POINT (default)"
      end
      
      direction_explanation = case direction
      when "up"
        "Component will be created by extruding upward in +Z direction."
      when "down"
        "Component will be created by extruding downward in -Z direction."
      when "forward"
        "Component will be created by extruding forward in +Y direction."
      when "back"
        "Component will be created by extruding backward in -Y direction."
      when "right"
        "Component will be created by extruding rightward in +X direction."
      when "left"
        "Component will be created by extruding leftward in -X direction."
      when "auto"
        "Component will be created using automatic direction (upward)."
      else
        "Component will be created with standard upward extrusion."
      end
      
      result = {
        type: type,
        requested_position: position,
        requested_dimensions: dimensions,
        direction: direction,
        origin_mode: origin_mode,
        positioning_method: origin_explanation.downcase.gsub(" ", "_"),
        center_point: [center_x, center_y, center_z],
        bounds: {
          min: min_point,
          max: max_point,
          width: width,
          height: height,
          depth: depth,
          corners: corners
        },
        positioning_explanation: "Position [#{requested_x}, #{requested_y}, #{requested_z}] interpreted as #{origin_explanation}. #{direction_explanation} Component center will be at [#{center_x}, #{center_y}, #{center_z}], resulting in bounds from #{min_point} to #{max_point}.",
        coordinate_system: {
          description: "X+ = Right, Y+ = Forward/Depth, Z+ = Up",
          growth_pattern: "Component grows equally in all directions from calculated center position"
        },
        directional_info: {
          origin_explanation: origin_explanation,
          direction_explanation: direction_explanation,
          center_offset: [center_x - requested_x, center_y - requested_y, center_z - requested_z]
        },
        success: true
      }
      
      Logging.log "Position preview result: #{result.inspect}"
      result
    end

    private

    def self.collect_all_entities(entities, collector)
      entities.each do |entity|
        collector << entity
        if entity.respond_to?(:entities)
          collect_all_entities(entity.entities, collector)
        end
      end
    end

    def self.get_component_center(component)
      bounds = component.bounds
      center = bounds.center
      [center.x.to_f, center.y.to_f, center.z.to_f]
    end

    def self.get_component_origin(component)
      if component.respond_to?(:transformation)
        origin = component.transformation.origin
        [origin.x.to_f, origin.y.to_f, origin.z.to_f]
      else
        # For entities without transformation, use bounds min point
        bounds = component.bounds
        [bounds.min.x.to_f, bounds.min.y.to_f, bounds.min.z.to_f]
      end
    end

    def self.get_closest_bounds_points(comp1, comp2)
      bounds1 = comp1.bounds
      bounds2 = comp2.bounds
      
      # Get all corner points for both components
      corners1 = get_bounds_corners(bounds1)
      corners2 = get_bounds_corners(bounds2)
      
      # Find the pair of points with minimum distance
      min_distance = Float::INFINITY
      closest_points = [nil, nil]
      
      corners1.each do |point1|
        corners2.each do |point2|
          distance = calculate_distance_between_points(point1, point2)
          if distance < min_distance
            min_distance = distance
            closest_points = [point1, point2]
          end
        end
      end
      
      closest_points
    end

    def self.get_bounds_corners(bounds)
      min_pt = bounds.min
      max_pt = bounds.max
      
      [
        [min_pt.x.to_f, min_pt.y.to_f, min_pt.z.to_f],  # min corner
        [max_pt.x.to_f, min_pt.y.to_f, min_pt.z.to_f],  # max x
        [min_pt.x.to_f, max_pt.y.to_f, min_pt.z.to_f],  # max y
        [min_pt.x.to_f, min_pt.y.to_f, max_pt.z.to_f],  # max z
        [max_pt.x.to_f, max_pt.y.to_f, min_pt.z.to_f],  # max x,y
        [max_pt.x.to_f, min_pt.y.to_f, max_pt.z.to_f],  # max x,z
        [min_pt.x.to_f, max_pt.y.to_f, max_pt.z.to_f],  # max y,z
        [max_pt.x.to_f, max_pt.y.to_f, max_pt.z.to_f]   # max corner
      ]
    end

    def self.calculate_distance_between_points(point1, point2)
      dx = point2[0] - point1[0]
      dy = point2[1] - point1[1]
      dz = point2[2] - point1[2]
      Math.sqrt(dx*dx + dy*dy + dz*dz)
    end

    def self.set_marker_material(group, color_name)
      model = Sketchup.active_model
      materials = model.materials
      
      # Map color names to RGB values
      color_map = {
        "red" => [255, 0, 0],
        "green" => [0, 255, 0],
        "blue" => [0, 0, 255],
        "yellow" => [255, 255, 0],
        "orange" => [255, 165, 0],
        "purple" => [128, 0, 128],
        "cyan" => [0, 255, 255],
        "magenta" => [255, 0, 255]
      }
      
      rgb = color_map[color_name.downcase] || [255, 0, 0]  # Default to red
      
      # Create or find material
      material_name = "marker_#{color_name}"
      material = materials[material_name]
      
      unless material
        material = materials.add(material_name)
        material.color = rgb
      end
      
      # Apply material to all faces in the group
      group.entities.grep(Sketchup::Face) do |face|
        face.material = material
      end
      
      material
    end

    def self.calculate_positioning_accuracy(params, verification)
      requested_position = params["position"] || [0, 0, 0]
      actual_center = verification[:bounds][:center]
      
      # Calculate distance between requested and actual positions
      error_distance = calculate_distance_between_points(requested_position, actual_center)
      
      {
        requested_position: requested_position,
        actual_center: actual_center,
        error_distance: error_distance,
        accuracy_level: error_distance < 0.001 ? "excellent" : error_distance < 0.1 ? "good" : error_distance < 1.0 ? "fair" : "poor"
      }
    end
  end
end 