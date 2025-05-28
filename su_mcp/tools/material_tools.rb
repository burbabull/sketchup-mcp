module SketchupMCP
  module MaterialTools
    def self.set_material(params)
      Logging.log "Setting material with params: #{params.inspect}"
      model = Sketchup.active_model
      
      # Handle ID format - strip quotes if present
      id_str = params["id"].to_s.gsub('"', '')
      Logging.log "Looking for entity with ID: #{id_str}"
      
      entity = model.find_entity_by_id(id_str.to_i)
      
      if entity
        Logging.log "Found entity: #{entity.inspect}"
        
        material_name = params["material"].to_s.downcase.strip
        Logging.log "Setting material to: #{material_name}"
        
        # Check if material already exists in model
        existing_material = model.materials.find { |m| m.name.downcase == material_name }
        
        if existing_material
          material = existing_material
          Logging.log "Using existing material: #{material.name}"
        else
          # Create a new material
          material = model.materials.add(material_name)
          Logging.log "Created new material: #{material.name}"
          
          # Set material properties based on name
          set_material_properties(material, material_name)
        end
        
        # Apply the material to the entity
        apply_material_to_entity(entity, material)
        
        { success: true, id: entity.entityID, material: material.name }
      else
        raise "Entity not found: #{id_str}"
      end
    end
    
    def self.set_material_properties(material, material_name)
      case material_name
      # Basic colors
      when "red"
        material.color = Sketchup::Color.new(255, 0, 0)
      when "green"
        material.color = Sketchup::Color.new(0, 255, 0)
      when "blue"
        material.color = Sketchup::Color.new(0, 0, 255)
      when "yellow"
        material.color = Sketchup::Color.new(255, 255, 0)
      when "cyan", "turquoise"
        material.color = Sketchup::Color.new(0, 255, 255)
      when "magenta", "purple"
        material.color = Sketchup::Color.new(255, 0, 255)
      when "white"
        material.color = Sketchup::Color.new(255, 255, 255)
      when "black"
        material.color = Sketchup::Color.new(0, 0, 0)
      when "gray", "grey"
        material.color = Sketchup::Color.new(128, 128, 128)
      when "orange"
        material.color = Sketchup::Color.new(255, 165, 0)
      when "pink"
        material.color = Sketchup::Color.new(255, 192, 203)
      
      # Building materials
      when "concrete"
        material.color = Sketchup::Color.new(192, 192, 192)
        material.alpha = 1.0
      when "cement"
        material.color = Sketchup::Color.new(169, 169, 169)
      when "stone", "granite"
        material.color = Sketchup::Color.new(105, 105, 105)
      when "marble"
        material.color = Sketchup::Color.new(248, 248, 255)
      when "brick"
        material.color = Sketchup::Color.new(178, 34, 34)
      when "limestone"
        material.color = Sketchup::Color.new(250, 240, 230)
      when "sandstone"
        material.color = Sketchup::Color.new(244, 164, 96)
      
      # Wood materials
      when "wood", "pine"
        material.color = Sketchup::Color.new(222, 184, 135)
      when "oak"
        material.color = Sketchup::Color.new(184, 134, 72)
      when "mahogany"
        material.color = Sketchup::Color.new(192, 64, 0)
      when "walnut"
        material.color = Sketchup::Color.new(101, 67, 33)
      when "cherry"
        material.color = Sketchup::Color.new(184, 75, 48)
      when "maple"
        material.color = Sketchup::Color.new(248, 231, 185)
      
      # Metals
      when "steel", "iron"
        material.color = Sketchup::Color.new(105, 105, 105)
        material.alpha = 1.0
      when "aluminum", "aluminium"
        material.color = Sketchup::Color.new(192, 192, 192)
      when "copper"
        material.color = Sketchup::Color.new(184, 115, 51)
      when "gold"
        material.color = Sketchup::Color.new(255, 215, 0)
      when "silver"
        material.color = Sketchup::Color.new(192, 192, 192)
      
      # Glass and plastics
      when "glass"
        material.color = Sketchup::Color.new(173, 216, 230)
        material.alpha = 0.3
      when "plastic"
        material.color = Sketchup::Color.new(255, 255, 255)
      
      else
        # Handle hex color codes
        if material_name.start_with?("#") && material_name.length == 7
          begin
            r = material_name[1..2].to_i(16)
            g = material_name[3..4].to_i(16)
            b = material_name[5..6].to_i(16)
            material.color = Sketchup::Color.new(r, g, b)
            Logging.log "Applied hex color: #{material_name}"
            return
          rescue
            Logging.log "Failed to parse hex color: #{material_name}"
          end
        end
        
        # Handle RGB values in format "rgb(255,0,0)"
        if material_name.match(/rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/)
          begin
            r, g, b = $1.to_i, $2.to_i, $3.to_i
            material.color = Sketchup::Color.new(r, g, b)
            Logging.log "Applied RGB color: #{material_name}"
            return
          rescue
            Logging.log "Failed to parse RGB color: #{material_name}"
          end
        end
        
        # Try to find similar material name (fuzzy matching)
        similar_material = find_similar_material(material_name)
        if similar_material
          Logging.log "Using similar material '#{similar_material}' for '#{material_name}'"
          set_material_properties(material, similar_material)
          return
        end
        
        # Default to a neutral wood color for unknown materials
        Logging.log "Unknown material '#{material_name}', using default wood color"
        material.color = Sketchup::Color.new(184, 134, 72)
      end
    end
    
    def self.find_similar_material(material_name)
      # Define material groups for fuzzy matching
      material_groups = {
        "wood" => ["wood", "oak", "pine", "maple", "cherry", "walnut", "mahogany"],
        "metal" => ["steel", "iron", "aluminum", "copper", "brass", "bronze", "chrome"],
        "stone" => ["concrete", "stone", "granite", "marble", "limestone", "sandstone"],
        "glass" => ["glass", "crystal", "transparent"],
        "plastic" => ["plastic", "polymer", "vinyl", "acrylic"]
      }
      
      # Check for partial matches
      material_groups.each do |group_name, materials|
        materials.each do |mat|
          if material_name.include?(mat) || mat.include?(material_name)
            return mat
          end
        end
      end
      
      # Check for common misspellings or variations
      variations = {
        "concret" => "concrete",
        "alumnium" => "aluminum",
        "aluminium" => "aluminum",
        "stil" => "steel",
        "steal" => "steel",
        "wod" => "wood"
      }
      
      variations.each do |typo, correct|
        if material_name.include?(typo)
          return correct
        end
      end
      
      nil
    end
    
    def self.apply_material_to_entity(entity, material)
      if entity.respond_to?(:material=)
        entity.material = material
        Logging.log "Applied material directly to entity"
      elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        # For groups and components, apply to all faces
        entities = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        face_count = 0
        entities.grep(Sketchup::Face).each do |face|
          face.material = material
          face_count += 1
        end
        Logging.log "Applied material to #{face_count} faces in #{entity.typename}"
      else
        Logging.log "Warning: Unable to apply material to #{entity.typename}"
      end
    end
  end
end 