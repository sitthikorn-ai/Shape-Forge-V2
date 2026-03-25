module VBO::ShapeForge
    class Options
        attr_accessor :click_edit, :delete_edges, :scale_rebuild, :pinned

        def initialize
            load
        end
        def load
            @click_edit = false
            @scale_rebuild = false
            @delete_edges = true
            @pinned = true
            h = Sketchup.read_default('VBO ShapeForge', 'Options')
            read(h) if !h.nil? && !h.empty? && h.length == self.instance_variables.length
        end

        def to_h
            self.instance_variables.map{|c| [c, self.instance_variable_get(c)]}.to_h
        end
        def save
            hash = self.to_h
            Sketchup.write_default('VBO ShapeForge', 'Options', hash)
        end
        def read(h)
            self.instance_variables.each{|c|
                self.instance_variable_set(c, h[c])
            }
            save
            self
        end
    end
    class OptionsForgeStructure

        attr_accessor :click_edit, :delete_edges, :scale_rebuild, :pinned, :dialog_position

        def initialize
            load
        end
        def load
            @click_edit = false
            @scale_rebuild = false
            @delete_edges = true
            @pinned = false
            @dialog_position = 'any'
            h = Sketchup.read_default('VBO ShapeForge', 'OptionsForgeStructure')
            read(h) if !h.nil? && !h.empty? && h.length == self.instance_variables.length
        end

        def to_h
            self.instance_variables.map{|c| [c, self.instance_variable_get(c)]}.to_h
        end
        def save
            hash = self.to_h
            Sketchup.write_default('VBO ShapeForge', 'OptionsForgeStructure', hash)
        end
        def read(h)
            self.instance_variables.each{|c|
                self.instance_variable_set(c, h[c])
            }
            save
            self
        end
    end
    def self.options
    end
end
