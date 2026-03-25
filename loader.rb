
require 'sketchup.rb'
require 'securerandom'
Sketchup.require File.join(File.dirname(__FILE__), 'main')
Sketchup.require File.join(File.dirname(__FILE__), 'observers')
Sketchup.require File.join(File.dirname(__FILE__), 'options')
Sketchup.require File.join(File.dirname(__FILE__), 'sub_tools')
# Sketchup.require File.join(File.dirname(__FILE__), 'assembly')
# Sketchup.require File.join(File.dirname(__FILE__), 'assembly_controller')
module VBO::ShapeForge
    file = __FILE__
    COLOR_MEM_ASS_PATH = Sketchup::Color.new('magenta')
    COLOR_POINT_HOVERED = Sketchup::Color.new('blue')
    COLOR_POINT_SNAP = Sketchup::Color.new('red')
    COLOR__MEM_ASS_PATH_HOVERED = Sketchup::Color.new('blue')
    unless file_loaded? file

      sub = UI.menu("Extensions").add_submenu('Shape Forge')


   		tb = UI::Toolbar.new( 'Shape Forge' )


        path_to_images = File.join(File.dirname(__FILE__), 'images')
        command2 = UI::Command.new('Shape Member Dialog'){
            self.show_profile_dialog
        }
        command2.small_icon = File.join(path_to_images,"tol.png")
        command2.large_icon = File.join(path_to_images,"tol.png")
        command2.tooltip = 'Shape Forge Dialog'
        command2.status_bar_text = 'Shapes Manager'
        # command2.set_validation_proc {
        #     if VBO::ShapeForge.profile_dialog_visible?
        #       MF_CHECKED
        #     else
        #       MF_UNCHECKED
        #     end
        #   }

        tb.add_item(command2)
        sub.add_item(command2)

        # command2 = UI::Command.new('ForgeStructure Dialog'){
        #     self.show_assembly_dialog
        # }
        # command2.small_icon = File.join(path_to_images,"ass.svg")
        # command2.large_icon = File.join(path_to_images,"ass.svg")
        # command2.tooltip = 'ForgeStructure Dialog'
        # command2.status_bar_text = 'ForgeStructure Manager'

        # # command2.set_validation_proc {
        # #     if VBO::ShapeForge.assembly_dialog_visible?
        # #       MF_CHECKED
        # #     else
        # #       MF_UNCHECKED
        # #     end
        # #   }

        # tb.add_item(command2)

        command2 = UI::Command.new('Smart Objects'){
          self.show_smart_object_dialog
        }
        command2.small_icon = File.join(path_to_images,"smart_object.svg")
        command2.large_icon = File.join(path_to_images,"smart_object.svg")
        command2.tooltip = 'Smart Objects'
        command2.status_bar_text = 'Choose and Draw Smart Objects'

        tb.add_item(command2)
        sub.add_item(command2)


        command2 = UI::Command.new('Wrench Tool'){
          t = WrenchTool.new
          Sketchup.active_model.tools.push_tool t
        }
        command2.small_icon = File.join(path_to_images,"wrench.svg")
        command2.large_icon = File.join(path_to_images,"wrench.svg")
        command2.tooltip = 'Wrench Tool'
        command2.status_bar_text = 'Adjust Forge Elements'

        tb.add_item(command2)
        sub.add_item(command2)

        sub.add_item('Profiles Report') {self.manager}

        file_loaded file
        enable_shapeforge_app_observer
        # Overlay-based control removed per request; control Assembly Click-Edit from dialog only
     end
end
