module VBO::ShapeForge
  class FenceElement

    attr_accessor :name, :global_z_offset, :x_offset, :y_offset, :z_offset, :start_setback, :junction_setback, :end_setback, :enabled, :group, :use_global_up_offset, :ui_id

    def initialize(object = nil)
      require 'SecureRandom'
      @name = ""
      @global_z_offset = 0.0
      @x_offset = 0.0
      @y_offset = 0.0
      @start_setback = 0.0
      @junction_setback = 0.0
      @end_setback = 0.0
      @enabled = true
      @use_global_up_offset = false
      @ui_id = SecureRandom.uuid
    end
    def assign(hash)
      hash.each do |key, value|
        instance_variable_set(key.to_sym, value) if instance_variables.include?(key.to_sym)
      end
      #   [c, instance_variable_get(c)]
      # }.to_h
    end
    def offset_chain(chain, use_global = false)

      #calculate the offset profile location
      y_offset = self.y_offset
      x_offset = self.x_offset
      if use_global
        chain.offset!(x_offset,0)
        chain.offset_global_z!(y_offset)
      else
        if y_offset!= 0.0 or x_offset!= 0.0
          chain.offset!(x_offset,y_offset)
        end
      end
      chain
    end
	end

	class Post < FenceElement
    attr_accessor :real_spacing, :cal_junctions, :cal_segments
    attr_reader :instances, :spacing, :layout, :at_start, :at_junction, :at_end, :at_infill, :junction_angle, :rotation, :stay_vertical, :mirror, :max_spacing, :horizontal_spacing, :layer_name, :component_defn_guid, :at_left_junction, :at_right_junction, :componentGUID

    attr_writer :spacing, :layout, :at_start, :at_junction, :at_end, :at_infill, :junction_angle, :rotation, :stay_vertical, :mirror, :max_spacing, :horizontal_spacing, :layer_name, :at_left_junction, :at_right_junction, :componentGUID, :horiz_spacing, :use_advanced_junction_setbacks, :pre_left_junction_setback, :post_left_junction_setback, :pre_right_junction_setback, :post_right_junction_setback, :force_start_end

    def initialize(object = nil)
      super
      @component_name = ""
      @component_defn_guid = nil
      @spacing = 96.0
      @layout = "From Start"
      @at_start = "true"
      @at_junction = "true"
      @at_end = "true"
      @at_infill = "true"
      @junction_angle = 60.0
      @rotation = "0"
      @stay_vertical = "true"
      @mirror = "false"
      @max_spacing = "true"
      @horizontal_spacing = "true"
      @layer_name = Sketchup.active_model.layers[0].display_name
      @instances = {}
      @real_spacing = @spacing
      if object.class == String
        load_from_string(object)
      end

    end

    def valid?

      valid = true
      valid = false if self.component_definition == nil || self.component_definition.to_s.include?("Delete")
      valid = false if @spacing.to_f <= 0.0
      return valid

    end

    def ==(po)
      # po.component_definition == self.component_definition
      po.ui_id == self.ui_id
    end

    def clear_instances()

      @instances = {}

    end

    def add_instance(trans,edge)

      unless @instances[edge]
        @instances[edge] = []
      end

      @instances[edge].push(trans)


    end

    def component_name

      defn = self.component_definition
      if defn
        name = defn.name
      else
        name = nil
      end

      return name

    end
    def get_faces(path = [])
      if path.is_a?(Sketchup::ComponentDefinition)
        ents =path.entities
        path = []
      else
        ents = path.empty? ? Sketchup.active_model.active_entities : path[-1].definition.entities
      end
      results = []
      tr = Sketchup::InstancePath.new(path).transformation
      ents.each{|e|
        if e.is_a?(Sketchup::Face) && e.area > 3
          pts = e.outer_loop.vertices.map{|v| v.position.transform(tr)}
          results << Geom.tesselate(pts)
        end
        if e.respond_to?(:definition)
          results += get_faces(path + [e])
        end
      }
      results
    end
    def component_name=(value)
      #  UI.messagebox "component_name = #{value}"
      @component_name = value
      definition_list = Sketchup.active_model.definitions
      defn = definition_list[value]
      if defn
        @component_defn_guid = defn.guid
      else
        @component_defn_guid = ""
      end
    end

    def component_definition
      definition_list = Sketchup.active_model.definitions
      defn = definition_list[@component_name]
      if defn == nil && @component_defn_guid
        defn = definition_list[@component_defn_guid]
        @component_name = defn.name if defn
      end
      return defn
    end

    def horizontal_layout?
      @horizontal_spacing.to_s == "true"
    end

    def fixed_spacing?
      @max_spacing.to_s != "true"
    end

    def stay_vertical?
      @stay_vertical.to_s == "true"
    end

    def mirror?
      @mirror.to_s == "true"
    end
    def build_cache
      # puts "build cache"
      defn = self.component_definition
      if defn
        cache = get_faces(defn)
        @cache = cache.flatten
      end
    end

    def load_from_string(string)
      return if string == ""
      if string.include?("|")
        arr = string.split("|")
        @name = arr[0]
        @spacing = arr[2].to_f
        @layout = arr[3]
        @at_start = arr[4]
        @at_junction = arr[5]
        @at_end = arr[6]
        @at_infill = arr[7]
        @x_offset = arr[8].to_f
        @y_offset = arr[9].to_f
        @start_setback = arr[10].to_f
        @junction_setback = arr[11].to_f
        @end_setback = arr[12].to_f
        @rotation = arr[13]
        @stay_vertical = arr[14]
        @mirror = arr[15]
        @global_z_offset = arr[16].to_f
        guid = arr[17]
        @layer_name = arr[18].to_s
        @junction_angle = arr[19].to_f
        @max_spacing = arr[20]
        @horizontal_spacing = arr[21]
        @enabled = arr[22]
        @instances = eval(arr[23]).map{|k,v|
          [
            k.map{|c| Geom::Point3d.new(c)},
            v.map{|c| Geom::Transformation.new(c)}
          ]
        }.to_h
        if @component_name.to_s != ""
          defn  = defns[@component_name]
           if defn
            component_name = defn.name
          else
            component_name = arr[1]
          end
        elsif guid
          defns = Sketchup.active_model.definitions
          defn = defns[guid]
          if defn
            component_name = defn.name
          else
            component_name = arr[1]
          end
        else
          component_name = arr[1]
        end
      else
        str = JSON.parse(string).map{|k,v|
          [
            VBO::ShapeForge.camel_to_snake(k),
            v
          ]
        }.to_h
        str.keys.each{|v|
          instance_variable_set(v, str[v])
          #puts ("#{v} = #{str[v]}")
        }
        @horizontal_spacing = @horiz_spacing
        @component_defn_guid = @componentGUID
        guid = @componentGUID

        #puts guid
        #puts Sketchup.active_model.definitions[guid]
        defns = Sketchup.active_model.definitions
        if @component_name.to_s != ""
          defn  = defns[@component_name]
          if defn
            component_name = defn.name
          else
            component_name = @name
          end
        elsif guid
          defn = defns[guid]
          if defn
            component_name = defn.name
          else
            component_name = @name
          end
        else
          component_name = @name
        end
      end
      @at_junction = "Before" if @at_junction == true
      @instances = eval(@instances) if @instances.class == String
      @instances = @instances.map{|k,v|
        #UI.messagebox v
        k = eval(k) if k.class == String
        v = eval(v) if v.class == String
        [
          k.map{|c| Geom::Point3d.new(c)},
          v.map{|c| Geom::Transformation.new(c)}
        ]
      }.to_h
      @layer_name = 'Untagged' if @layer_name == 'Layer0'
      @name = @component_name if @name == nil || @name == ""
    end #load properties
    def to_h
      ha = instance_variables.find_all{|c|
        c != :@group && c != :@cal_junctions && c != :@cal_segments
      }.map{|c|
        [
          VBO::ShapeForge.snake_to_camel(c),
          VBO::ShapeForge.save_out([instance_variable_get(c)])[0]
        ]
      }.to_h

      ha.each{|k,v|
        if v.to_s.include?('Delete')
          ha[k] = nil
        end
      }
      ha
    end
    #
    def to_s

      # defn = self.component_definition
      # guid = defn ? defn.guid : ""
      # arr = [@name,@component_name,@spacing,@layout,@at_start,@at_junction,@at_end,@at_infill,@x_offset,@y_offset,@start_setback,@junction_setback,@end_setback, @rotation,@stay_vertical,@mirror,@global_z_offset,guid,@layer_name, @junction_angle, @max_spacing,@horizontal_spacing,@enabled, @instances.map{|k,v| [k.map{|c| c.to_a},v.map{|c| c.to_a}]}.to_h]
      # return arr.join("|")
      to_h.to_json
    end #to_s

    def at_start?

      @at_start.to_s == "true"

    end

    def at_end?
      @at_end.to_s == "true"
    end

    def at_junction?
      @at_junction.to_s == "true"
    end

    def at_infill?
      @at_infill.to_s == "true"
    end
    def draw(view)
      # puts "draw post: #{@cache}"
      defn = self.component_definition
      if defn
        @instances.each{|pt, trs|
          trs.each{|tr|
            view.draw(GL_TRIANGLES, @cache.map{|point| point.transform(tr) } ) if @cache
          }
        }
      end
    end
	end

	class Rail < FenceElement
    attr_reader :profile, :allow_slope
    attr_writer :profile, :allow_slope

    def initialize(object = nil)

      @profile = nil
      @allow_slope = "true"
      super
      if object.class == String

        load_from_string(object)
      end
    end
    def ==(rail)
      rail.profile == self.profile
    end
    #populates the attributes of the rail from the string
    def load_from_string(string)
      return if string == ""
      unless string.start_with?('{')
        arr = string.split(";")
        @name = arr[0]
        @profile = Shape.new(arr[1])
        @x_offset = arr[2].to_f
        @y_offset = arr[3].to_f
        @z_offset = arr[4].to_f
        @start_setback = arr[5].to_f
        @junction_setback = arr[6].to_f
        @end_setback = arr[7].to_f
        @allow_slope = arr[8] == "true" ? true : false
        @global_z_offset = arr[9].to_f
        @enabled = arr[10]
      else

        str = JSON.parse(string).map{|k,v|
          [
            VBO::ShapeForge.camel_to_snake(k),
            v
          ]
        }.to_h
        str.keys.each{|v|
          instance_variable_set(v, str[v])
        }

        @profile = Shape.new(@profile).to_s
        @layer_name = 'Untagged' if @layer_name == 'Layer0'

      end
    end #load properties

    ##
    def valid?

      v = true
      if @profile == nil or @profile == ""
        v = false
      end

      return v

    end
    def to_h
      ha = instance_variables.find_all{|c|
        c != :@group
      }.map{|c|
        [
          VBO::ShapeForge.snake_to_camel(c),
          VBO::ShapeForge.save_out([instance_variable_get(c)])[0]
        ]
      }.to_h

      ha.each{|k,v|
        if v.to_s.include?('Delete')
          ha[k] = nil
        end
      }
      ha
    end
    #
    def to_s

      # arr = [@name,@profile,@x_offset,@y_offset,@z_offset,@start_setback,@junction_setback,@end_setback,@allow_slope,@global_z_offset,@enabled]
      # return arr.join(";")
      to_h.to_json

    end #to_s

    ##


	end

  class Span < FenceElement
    attr_accessor :type, :profile, :component_name, :componentGUID, :sub_assembly, :support_post_index, :sag, :sag_divisions, :scale_to_fit, :allow_slope, :allow_curve, :auto_trim, :shear_on_slope, :layer_name, :pattern, :cross_junctions, :glue_to_support, :component_defn_guid

    def initialize(object = nil)
      super

      @type = 0
      @profile = nil
      @component_name = ""
      @componentGUID = ""
      @sub_assembly = nil
      @support_post_index = 0
      @sag = 0.0
      @sag_divisions = 10
      @scale_to_fit = true
      @allow_slope = true
      @allow_curve = false
      @auto_trim = false
      @shear_on_slope = false
      @layer_name = "Layer0"
      @pattern = 0
      @cross_junctions = false
      @glue_to_support = false

      if object.class == String
        load_from_string(object)
      end
    end

    def component_definition
      definition_list = Sketchup.active_model.definitions
      if @component_name
        defn = definition_list[@component_name]
        if defn == nil && @component_defn_guid
          defn = definition_list[@component_defn_guid]
          @component_name = defn.name if defn
        end
        defn
      end
    end

    def valid?
      true
    end

    def load_from_string(string)
      return if string == ""

      str = JSON.parse(string).map{|k,v|
        [
          VBO::ShapeForge.camel_to_snake(k),
          v
        ]
      }.to_h
      str.keys.each{|v|
        instance_variable_set(v, str[v])
        #puts ("#{v} = #{str[v]}")
      }
      case @type
      when 0
        @profile = Shape.new(@profile)
        @component_name = nil
        @componentGUID = nil
        @component_defn_guid = nil
        @assembly = nil
        # @global_z_offset = @y_offset if @use_global_up_offset

      when 1
        @profile = nil
        @assembly = nil

        @component_defn_guid = @componentGUID
        # @global_z_offset = @y_offset if @use_global_up_offset
        guid = @componentGUID
        @sag = nil
        @sag_divisions = nil

        if guid
          defns = Sketchup.active_model.definitions
          defn = defns[guid]
          if defn
            self.component_name = defn.name
          else
            self.component_name = @name
          end
        else
          self.component_name = @name
        end
      when 2
        @profile = nil
        @component_name = nil
        @componentGUID = nil
        @component_defn_guid = nil
        # @global_z_offset = @y_offset if @use_global_up_offset

      end


      @layer_name = 'Untagged' if @layer_name == 'Layer0'
      @name = "Post#{@support_post_index}.Suport" if @name.to_s.empty?
    end

    def to_h
      ha = instance_variables.find_all{|c|
        c != :@group
      }.map{|c|
        [
          VBO::ShapeForge.snake_to_camel(c),
          VBO::ShapeForge.save_out([instance_variable_get(c)])[0]
        ]
      }.to_h

      ha.each{|k,v|
        if v.to_s.include?('Delete')
          ha[k] = nil
        end
      }
      ha
    end
    def to_s
      to_h.to_json
    end
    def inspect
      to_h
    end
  end

end	# module VBO::ShapeForge
