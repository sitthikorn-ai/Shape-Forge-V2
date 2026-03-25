require 'sketchup.rb'
Sketchup.require File.join(File.dirname(__FILE__), 'main')
Sketchup.require File.join(File.dirname(__FILE__), 'member')
Sketchup.require File.join(File.dirname(__FILE__), 'methods')
Sketchup.require File.join(File.dirname(__FILE__), 'options')
Sketchup.require File.join(File.dirname(__FILE__), 'dialog')

module VBO::ShapeForge
	class << self
		attr_accessor :path_edit_entities, :profile_dialog, :assembly_dialog, :debug_mode
	end
	@debug_mode = true
	class ShapeForgeEditObserver < Sketchup::ModelObserver
		attr_accessor :last_path, :last_edit, :last_join
		def onActivePathChanged(model)
			path =  model.active_path.to_a
			member =  VBO::ShapeForge::Identify.profile_member?(path.to_a[-1])
			profile_temp = path[-1] && path[-1].get_attribute("VBO ShapeForge", "Shape Temporary")
			if path.to_a != @last_path.to_a
				if @last_path && @last_edit && !@last_path.empty?
					member =  VBO::ShapeForge::Identify.profile_member?(@last_path.to_a[-1])
					if member
						# VBO::ShapeForge.debug "jump out"
						@last_edit = false
						VBO::ShapeForge.finished_edit_member(member)
						return
					end
				elsif @last_path && @last_edit_profile && !@last_path.empty?
					profile_temp = @last_path.to_a[-1].get_attribute("VBO ShapeForge", "Shape Temporary")
					if profile_temp
						@last_edit_profile = false
						VBO::ShapeForge.finished_edit_profile(@last_path.to_a[-1])
					end
				end
			end

			if path && member && !@last_join  && !@last_edit
				@last_join = true
				if member
					# VBO::ShapeForge.debug "jump in"
					VBO::ShapeForge.begin_edit_member(member)
					@last_edit = true
				end
			elsif path && profile_temp && !@last_join  && !@last_edit_profile
			   @last_join = true
				VBO::ShapeForge.begin_edit_profile(path[-1])
			   @last_edit_profile = true
			else
				@last_join = false
			end

			@last_path = path
		end

		#def onTransactionStart(model)
		#    VBO::ShapeForge.debug "onTransactionStart: #{model}"
		#end
		def onTransactionUndo(model)
			# VBO::ShapeForge.disable_shapeforge_sel_observer
			VBO::ShapeForge.check_undo(model)# if @last_edit# && !@last_edit_profile
			# VBO::ShapeForge.enable_shapeforge_sel_observer
		end
		def onTransactionRedo(model)
			# VBO::ShapeForge.disable_shapeforge_sel_observer
			VBO::ShapeForge.check_redo(model)# if !@last_edit && !@last_edit_profile
			# VBO::ShapeForge.enable_shapeforge_sel_observer
		end
	end

	class DialogModelObserver < Sketchup::ModelObserver
		def onTransactionUndo(model)
			# VBO::ShapeForge.disable_shapeforge_sel_observer
			VBO::ShapeForge.check_undo(model)
			# VBO::ShapeForge.enable_shapeforge_sel_observer
		end
		def onTransactionRedo(model)
			# VBO::ShapeForge.disable_shapeforge_sel_observer
			VBO::ShapeForge.check_redo(model)
			# VBO::ShapeForge.enable_shapeforge_sel_observer
		end
	end

	class ProfilesMakerToolsObserver < Sketchup::ToolsObserver
		def onActiveToolChanged(tools, tool_name, tool_id)
			# puts "onActiveToolChanged: #{tool_name}"
			if VBO::ShapeForge.profile_dialog_visible?
				# puts "oh yeah"
				if tool_name.to_s == "MoveTool"
					VBO::ShapeForge.disable_shapeforge_sel_observer
				else
					VBO::ShapeForge.enable_shapeforge_sel_observer
				end
			end
		end
	end

	class ShapeForgeEntitiesObserver < Sketchup::EntitiesObserver
		def onElementAdded(entities, entity)
		   entity.erase! if entity.is_a?(Sketchup::Face)
		end

		def onElementModified(entities, entity)
			#VBO::ShapeForge.debug "onElementModified: #{entity}"
		end

		def onElementRemoved(entities, entity_id)
			entities.add_cpoint Geom::Point3d.new [0,0,0] if  entities && !entities.to_s.include?('Delete') && entities.length == 0
		end
		def onEraseEntities(entities)
			entities.add_cpoint Geom::Point3d.new [0,0,0]  if  entities && !entities.to_s.include?('Delete') && entities.length == 0
		end
	end

	class ShapeForgeToolObserver < Sketchup::ToolsObserver
		attr_accessor :this_member
		def onActiveToolChanged(tools, tool_name, tool_id)
			sel = Sketchup.active_model.selection
			@action = nil if tool_name == 'ScaleTool'
		end

		def search_for_members(ent)
			list = []
			ent.find_all{|c| c.respond_to?(:definition)}.each{|c|
				member = VBO::ShapeForge::Identify.profile_member?(c)
				if member
					list << member
				else
					list += search_for_members(c.definition.entities)
				end
			}
			list
		end

		def search_for_assemblies(ent)
			list = []
			ent.find_all{|c| c.respond_to?(:definition)}.each{|c|
				ass = VBO::ShapeForge::Classify.assembly?(c)
				if ass
					list << ass
				else
					list += search_for_assemblies(c.definition.entities)
				end
			}
			list
		end

		def action
			Sketchup.active_model.start_operation "Rebuild", true
			members = search_for_members Sketchup.active_model.selection
			members.each{|member|
				profile = member.profile
				member.to_path
				Sketchup.active_model.selection.clear
				trim_attributes = [0,1].map{|i| member.get_attribute("cap_#{i}_trim")}
				edges = member.instance.explode.grep(Sketchup::Edge)
				Sketchup.active_model.selection.add edges
				VBO::ShapeForge.build_from_ents profile, Sketchup.active_model.selection, nil, trim_attributes
				Sketchup.active_model.selection.clear
				#edges.each{|c| c.erase!}
			}
			Sketchup.active_model.commit_operation
		end
		def onToolStateChanged(tools, tool_name, tool_id, tool_state)
			stt = "#{tool_name}:#{tool_state}"
			case stt
			when "ScaleTool:0"
				action if @action
			when "ScaleTool:1"
				@action = "hehe"
			end
		end
	end

	class ProfileForgeStructureMakerToolObserver < Sketchup::ToolsObserver
		attr_accessor :this_member
		def onActiveToolChanged(tools, tool_name, tool_id)
			sel = Sketchup.active_model.selection
			@action = nil if tool_name == 'ScaleTool'
		end

		def search_for_assemblies(ent)
			list = []
			ent.find_all{|c| c.respond_to?(:definition)}.each{|c|
				ass = VBO::ShapeForge::Classify.assembly?(c)
				if ass
					list << c
				else
					list += search_for_assemblies(c.definition.entities)
				end
			}
			list
		end

		def action
			Sketchup.active_model.start_operation "Rebuild", true
			asses = search_for_assemblies(Sketchup.active_model.selection)
			asses.each{|ass_gc|
				ass = VBO::ShapeForge::ForgeStructure.get(ass_gc)
				ass.draw_path
				edges = ass_gc.explode.grep(Sketchup::Edge)
				VBO::ShapeForge.build_assembly_from_ents ass, edges
				Sketchup.active_model.selection.clear
				#edges.each{|c| c.erase!}
			}
			Sketchup.active_model.commit_operation
		end
		def onToolStateChanged(tools, tool_name, tool_id, tool_state)
			stt = "#{tool_name}:#{tool_state}"
			case stt
			when "ScaleTool:0"
				action if @action
			when "ScaleTool:1"
				@action = "hehe"
			end
		end
	end

	def self.enable_ass_scale_tool_observer
		@ass_scale_tool_ob = ProfileForgeStructureMakerToolObserver.new
		Sketchup.active_model.tools.add_observer(@ass_scale_tool_ob)
	end

	def self.disable_ass_scale_tool_observer
		Sketchup.active_model.tools.remove_observer(@ass_scale_tool_ob)
	end

	class ShapeForgeAppObserver < Sketchup::AppObserver
		def expectsStartupModelNotifications()
		return true
		end

		def onNewModel(model)
			# puts "new model"
			kill_the_king
			@options = Options.new if @options.nil?
			@options.pinned = true
			@options.save
			if VBO::ShapeForge.assembly_dialog && VBO::ShapeForge.assembly_dialog.visible?
				VBO::ShapeForge.assembly_dialog.dialog.close
			end
			if VBO::ShapeForge.profile_dialog_visible?
				VBO::ShapeForge.profile_dialog.dialog.close
			end
		end

		def onOpenModel(model)
			# puts "open model"
			kill_the_king
			@options = Options.new if @options.nil?
			@options.pinned = true
			@options.save
			if VBO::ShapeForge.assembly_dialog && VBO::ShapeForge.assembly_dialog.visible?
				VBO::ShapeForge.assembly_dialog.dialog.close
			end
			if VBO::ShapeForge.profile_dialog_visible?
				VBO::ShapeForge.profile_dialog.dialog.close
			end
		end
		def kill_the_king
			nil
		end
		def onQuit()
			@options = Options.new if @options.nil?
			@options.pinned = true
			@options.save
		end
	end


	class ShapeForgeSelectionObserver < Sketchup::SelectionObserver
    attr_accessor :i
		def onSelectionBulkChange(selection)

			if VBO::ShapeForge.assembly_dialog_visible?
				edges = selection.any?{|c| c.is_a?(Sketchup::Edge) || VBO::ShapeForge::Classify.assembly?(c)}
				if edges && !VBO::ShapeForge.assembly_dialog.assembly.nil?
					VBO::ShapeForge.assembly_dialog.run_script(%Q{
						w2ui.toolbar.enable('apply');
						w2ui.toolbar.enable("reverse", "open_close");
					})
					if selection.length == 1 && VBO::ShapeForge::Classify.assembly?(selection.first)
						ass = VBO::ShapeForge::ForgeStructure.get(selection.first)
						dass = VBO::ShapeForge.assembly_dialog.assembly
						if ass.fence.rails == dass.fence.rails && ass.fence.posts == dass.fence.posts
							VBO::ShapeForge.assembly_dialog.run_script(%Q{
								$('#assembly-check').html('');
							})
						else
							VBO::ShapeForge.assembly_dialog.run_script(%Q{
								$('#assembly-check').html('<i id="same_ass" class="fa fa-exclamation-triangle fa-lg"></i>');
							})
						end
					end
				else
					VBO::ShapeForge.assembly_dialog.run_script(%Q{
						w2ui.toolbar.disable('apply');
						w2ui.toolbar.disable('reverse', "open_close");
					})
				end
				if selection.any?{|c| VBO::ShapeForge::Identify.profile_member?(c)}
					VBO::ShapeForge.assembly_dialog.run_script(%Q{
						w2ui.profile_grid_toolbar.enable("reverse_member", "open_close_member", 'apply_flask_rail');
					})
				elsif selection.any?{|c| c.is_a?(Sketchup::Edge)}
					VBO::ShapeForge.assembly_dialog.run_script(%Q{
						w2ui.profile_grid_toolbar.enable('apply_flask_rail');
					})
				else
					VBO::ShapeForge.assembly_dialog.run_script(%Q{
						w2ui.profile_grid_toolbar.disable("reverse_member", "open_close_member",'apply_flask_rail');
					})
				end
			else

			end
			VBO::ShapeForge.enable_overlay

			# If Assembly click-edit is enabled (from Overlays tray), jump into edit
			# when the user selects a single assembly container.
			begin
				ass_opts = VBO::ShapeForge::OptionsForgeStructure.new
				if ass_opts.click_edit && selection.length == 1 && VBO::ShapeForge::Classify.assembly?(selection.first)
					inst = selection.first
					# Enter the assembly container so ModelObserver can take over
					UI.start_timer(0.0, false) do
						begin
							if Sketchup.active_model && inst && inst.valid?
								path = Sketchup::InstancePath.new([inst])
								Sketchup.active_model.active_path = path if Sketchup.active_model.respond_to?(:active_path=)
							end
						rescue
							# ignore – selection might have changed
						end
					end
				end
			rescue
				# ignore
			end
			# @i = 0 if @i.nil?
			# if @i==0
				# VBO::ShapeForge.debug "select change #{selection}"

				if VBO::ShapeForge.profile_dialog_visible?

					unless Options.new.pinned
						VBO::ShapeForge.profile_dialog.refresh(1)
					else
						VBO::ShapeForge.profile_dialog.redraw
						VBO::ShapeForge.profile_dialog.run_script(%Q{
							if ( $('#selective').css('display') == 'block' &&  $('#selective').css('border-color') == "rgb(255, 0, 0)") {
								$('#clear').click();
								w2ui.profile_toolbar.disable('apply', 'apply_flask');
							}
						})
					end
				end
			# 	@i = 0
			# else
			# end
    end

    def onSelectionCleared(selection)
			#VBO::ShapeForge.debug "Clear"
			@id = UI.start_timer(0.01, false) {
				if selection.to_a.empty?
					VBO::ShapeForge.debug "Clear Selection #{selection}"
					VBO::ShapeForge.disable_overlay
					if VBO::ShapeForge.profile_dialog_visible?
						if !Options.new.pinned && !Sketchup.active_model.tools.active_tool.to_s.include?('VBO::ShapeForge::PTool')
							VBO::ShapeForge.profile_dialog.refresh(1)
						else
							#VBO::ShapeForge.show_dialog
							VBO::ShapeForge.profile_dialog.redraw
						end
					end
					#@i = 1
					if VBO::ShapeForge.assembly_dialog_visible?
						VBO::ShapeForge.assembly_dialog.run_script(%Q{
							//w2ui.toolbar.disable('apply');
						})
						VBO::ShapeForge.assembly_dialog.run_script(%Q{
							w2ui.profile_grid_toolbar.disable("reverse_member");
							w2ui.toolbar.disable("reverse");
						})
					else

					end
				end
				UI.stop_timer(@id)
			}
    end

		def onSelectionAdded(selection, entity)
			# VBO::ShapeForge.debug "add Selection #{selection}"

			if VBO::ShapeForge.profile_dialog_visible?
				if !Options.new.pinned
					VBO::ShapeForge.profile_dialog.refresh
				else
					VBO::ShapeForge.profile_dialog.redraw
					#VBO::ShapeForge.show_dialog
				end
			end
			if VBO::ShapeForge.assembly_dialog_visible?
				edges = selection.any?{|c| c.is_a?(Sketchup::Edge) || VBO::ShapeForge::Classify.assembly?(c)}
				# puts selection.to_a.to_s
				if edges && !VBO::ShapeForge.assembly_dialog.assembly.nil?
					VBO::ShapeForge.assembly_dialog.run_script(%Q{
						w2ui.toolbar.enable('apply');
					})
				else
					VBO::ShapeForge.assembly_dialog.run_script(%Q{
						//w2ui.toolbar.disable('apply');
					})
				end
			else

			end
		end
  end

	class ShapeForgeOptionsProviderObserver < Sketchup::OptionsProviderObserver
		def onOptionsProviderChanged(provider, name)
			#VBO::ShapeForge.debug "onOptionsProviderChanged: #{provider}, #{name}"
			VBO::ShapeForge.profile_dialog.redraw if VBO::ShapeForge.profile_dialog_visible?
		end
	end

	class ShapeForgeDefinitionsObserver < Sketchup::DefinitionsObserver
		def update_defs_list(definitions, definition)
			if definitions.include?(definition) && !definition.group?
				if VBO::ShapeForge.assembly_dialog_visible?
					script = %Q{
						definition_list = #{Sketchup.active_model.definitions.map{|c| c.name}.to_json};
						w2ui.component_grid.columns[0].editable.items = definition_list
					}
					# VBO::ShapeForge.debug 'update defs list'
					VBO::ShapeForge.assembly_dialog.run_script script
				end
			end
		end
		def onComponentAdded(definitions, definition)
			# VBO::ShapeForge.debug 'onComponentAdded'
			update_defs_list(definitions, definition)
			VBO::ShapeForge.manager_need_reload
		end

		def onComponentPropertiesChanged(definitions, definition)
			# VBO::ShapeForge.debug 'onComponentPropertiesChanged'
			update_defs_list(definitions, definition)
			VBO::ShapeForge.manager_need_reload
		end

		def onComponentRemoved(definitions, definition)
			# VBO::ShapeForge.debug 'onComponentRemoved'
			update_defs_list(definitions, definition)
			VBO::ShapeForge.manager_need_reload
		end

		def onComponentTypeChanged(definitions, definition)
			# VBO::ShapeForge.debug 'onComponentTypeChanged'
			update_defs_list(definitions, definition)
			VBO::ShapeForge.manager_need_reload
		end
	end

	def self.enable_def_ob
    disable_def_ob if @def_ob
    @def_ob = ShapeForgeDefinitionsObserver.new
    Sketchup.active_model.definitions.add_observer(@def_ob)
  end
  def self.disable_def_ob
    if @def_ob
      Sketchup.active_model.definitions.remove_observer(@def_ob)
      @def_ob = nil
    end
  end

	class ShapeForgeMaterialsObserver < Sketchup::MaterialsObserver
		def update_materials_list
			script = %Q{
        material_list = #{( [Sketchup.active_model.materials.unique_name("Default")] + Sketchup.active_model.materials.map{|c| c.name}).to_json};
      }
      if VBO::ShapeForge.profile_dialog_visible?
				VBO::ShapeForge.profile_dialog.run_script script
			elsif VBO::ShapeForge.assembly_dialog_visible?
				VBO::ShapeForge.assembly_dialog.run_script script
			end
		end

    def onMaterialAdd(materials, material)
			update_materials_list
    end
    def onMaterialChange(materials, material)
			update_materials_list
    end
    def onMaterialRemove(materials, material)
			update_materials_list
    end
    def onMaterialSetCurrent(materials, material)
			update_materials_list
    end
    def onMaterialUndoRedo(materials, material)
			update_materials_list
    end
  end

	def self.enable_mat_ob
    disable_mat_ob if @mat_ob
    @mat_ob = ShapeForgeMaterialsObserver.new
    Sketchup.active_model.materials.add_observer(@mat_ob)
  end
  def self.disable_mat_ob
    if @mat_ob
      Sketchup.active_model.materials.remove_observer(@mat_ob)
      @mat_ob = nil
    end
  end

	class ShapeForgeLayersObserver < Sketchup::LayersObserver
		def update_layers_list
			script = %Q{
				layer_list = #{( Sketchup.active_model.layers.map{|c|
				c.display_name}
			).to_json};
			}
			if VBO::ShapeForge.profile_dialog_visible?
				VBO::ShapeForge.profile_dialog.run_script script
			elsif VBO::ShapeForge.assembly_dialog_visible?
				VBO::ShapeForge.assembly_dialog.run_script script + %Q{
					w2ui.component_grid.columns[17].editable.items = layer_list
				}
			end
		end

    def onLayerAdded(layers, layer)
			unless layer.to_s.include?('Delete')
				layer.name = layer.name.gsub('*_*', ' ').gsub("%20", " ")
				update_layers_list
			end
    end
    def onLayerChanged(layers, layer)
			# layer.name = layer.name.gsub('*_*', ' ').gsub("%20", " ")
			update_layers_list
    end
    def onLayerRemoved(layers, layer)
			update_layers_list
    end
  end

	def self.enable_lay_ob
    disable_lay_ob if @lay_ob
    @lay_ob = ShapeForgeLayersObserver.new
    Sketchup.active_model.layers.add_observer(@lay_ob)
  end
  def self.disable_lay_ob
    if @lay_ob
      Sketchup.active_model.layers.remove_observer(@lay_ob)
      @lay_ob = nil
    end
  end

	def self.show_profile_dialog
		if @profile_dialog
			@profile_dialog.close_dialog
			@profile_dialog = nil
		else

			@profile_dialog = Dialog1.new
			@profile_dialog.create_dialog
		end
	end

	def self.show_assembly_dialog
		if @assembly_dialog
			@assembly_dialog.close_dialog
			@assembly_dialog = nil
		else

			@assembly_dialog = ForgeStructureController.new
			@assembly_dialog.show
		end
	end

	def self.enable_shapeforge_sel_observer
		disable_shapeforge_sel_observer
		# puts 'enable sel ob'
		@sel_ob = ShapeForgeSelectionObserver.new
		@sel_ob.i = nil
		Sketchup.active_model.selection.add_observer(@sel_ob)
	end
	def self.disable_shapeforge_sel_observer
		# VBO::ShapeForge.debug 'disable sel ob'
		if @sel_ob
			Sketchup.active_model.selection.remove_observer(@sel_ob)
			@sel_ob = nil
		end
	end

	def self.enable_shapeforge_unit_observer
		#VBO::ShapeForge.debug 'enable'
		disable_shapeforge_unit_observer
		@unit_ob = ShapeForgeOptionsProviderObserver.new

		options_provider = Sketchup.active_model.options["UnitsOptions"]
		options_provider.add_observer(@unit_ob)
	end
	def self.disable_shapeforge_unit_observer
		#VBO::ShapeForge.debug 'disable'
		if @unit_ob
			options_provider = Sketchup.active_model.options["UnitsOptions"]
			options_provider.remove_observer(@unit_ob)
			@unit_ob = nil
		end
	end


	def self.check_undo(model)
		# VBO::ShapeForge.debug "onTransactionUndo: #{model}"
		if model.active_path && Identify.profile_member?(model.active_path.to_a[-1]) && ![ "VBO_ShapeForge_EditPath", "VBO_ShapeForge_EditProfile"].include?(model.styles.selected_style.name) && !@is_editing && Options.new.click_edit
			# VBO::ShapeForge.debug "loop undo"
			# VBO::ShapeForge.disable_shapeforge_sel_observer
			Sketchup.send_action("editUndo:")
		else
			if !Identify.profile_member?(model.active_path.to_a[-1])
				Sketchup.active_model.styles.selected_style = @last_style if @last_style && !@last_style.to_s.include?('Delete')
				@is_editing = false if @is_editing
				@click_edit_ob.last_path = nil if @click_edit_ob
			end

			if VBO::ShapeForge.profile_dialog_visible?

					VBO::ShapeForge.debug "selection changed in undo?"
					unless Options.new.pinned
						VBO::ShapeForge.profile_dialog.refresh
					else
						VBO::ShapeForge.profile_dialog.redraw
						VBO::ShapeForge.profile_dialog.run_script(%Q{
							if ( $('#selective').css('display') == 'block' &&  $('#selective').css('border-color') == "rgb(255, 0, 0)") {
								$('#clear').click();
								w2ui.profile_toolbar.disable('apply');
							}
						})
					end
			end
		end

	end

	def self.check_redo(model)
		# VBO::ShapeForge.debug "onTransactionRedo: #{model}"
		if model.active_path && Identify.profile_member?(model.active_path.to_a[-1]) && ![ "VBO_ShapeForge_EditPath", "VBO_ShapeForge_EditProfile"].include?(model.styles.selected_style.name) && !@is_editing && Options.new.click_edit
			Sketchup.send_action("editRedo:")
		else

		end
		if VBO::ShapeForge.profile_dialog_visible? && !Options.new.pinned
			VBO::ShapeForge.profile_dialog.refresh
		end
	end

	def self.check_ass_undo(model)
		# VBO::ShapeForge.debug "onTransactionUndo: #{model}"
		if model.active_path && Identify.assembly?(model.active_path.to_a[-1]) && ![ "VBO_ShapeForge_EditPath", "VBO_ShapeForge_EditProfile"].include?(model.styles.selected_style.name) && !@is_editing && OptionsForgeStructure.new.click_edit
			# VBO::ShapeForge.debug "loop undo"
			Sketchup.send_action("editUndo:")
		else
		end

		if !Identify.assembly?(model.active_path.to_a[-1])
			Sketchup.active_model.styles.selected_style = @last_style if @last_style
			@is_editing = false
			@click_edit_ass_ob.last_path = nil if @click_edit_ass_ob
		end
	end

	def self.check_ass_redo(model)
		#VBO::ShapeForge.debug "onTransactionRedo: #{model}"
		if model.active_path && Identify.assembly?(model.active_path.to_a[-1]) && ![ "VBO_ShapeForge_EditPath", "VBO_ShapeForge_EditProfile"].include?(model.styles.selected_style.name) && !@is_editing && OptionsForgeStructure.new.click_edit
			Sketchup.send_action("editRedo:")
		else
		end
	end

	def self.last_path
		@click_edit_ob.last_path if @click_edit_ob
	end

	def self.edit_theme(type = "member")
		style_name = type == "member" ? "VBO_ShapeForge_EditPath" : "VBO_ShapeForge_EditProfile"
		style = Sketchup.active_model.styles[style_name]
		if style.nil?
			path = File.join(File.dirname(__FILE__), "examples/#{style_name}.style")
			Sketchup.active_model.styles.add_style path, false
			style = Sketchup.active_model.styles[style_name]
		end
		style
	end

	def self.begin_edit_member(member)

		@last_style = Sketchup.active_model.styles.selected_style
		@is_editing = true
		Sketchup.active_model.styles.selected_style = edit_theme
		@last_tool = Sketchup.active_model.tools.active_tool if Sketchup.version.to_i.ceil >= 19
		Sketchup.active_model.select_tool nil
		path = Sketchup.active_model.active_path
		transformation = Sketchup.active_model.edit_transform
		@path_edit_entities = member.definition.entities
		#Sketchup.active_model.commit_operation
		@last_edit_trans = member.to_path transformation
		#Sketchup.active_model.start_operation("jump", true)

		cpoint = @path_edit_entities.add_cpoint Geom::Point3d.new [0,0,0]

		enable_path_edit_entities_observer
	end

	def self.finished_edit_member(member)
		profile = member.profile
		profile.set_from_profile_member(member)
		entities = member.entities

		disable_path_edit_entities_observer

		Sketchup.active_model.start_operation "Finish Edit Path", true, false, true
		g = VBO::ShapeForge::Graph.new(entities)#.transform!(member.transformation)
		# need to convert to gloal transformation here because the transformation of the member is not global
		# member.re_coordinate(member.transformation, member.transformation.inverse)
		transformation = member.transformation
		member.instance.erase!
		sg = g.create_graph_from_simplified_graph(g.simply_graph)
		longest_paths = sg.merge_edges_to_polylines(sg.edges)
		longest_paths.each{|edge|
				pm = VBO::ShapeForge::ForgeElement.add(Sketchup.active_model.active_entities, edge)
				pm.set_from_profile!(profile)
				pm.re_coordinate(pm.transformation, pm.transformation.inverse)
				pm.transform!(transformation)
		}

		Sketchup.active_model.commit_operation
		if @last_tool && @last_tool.respond_to?(:last_path)
			if Sketchup.version.to_i.ceil >= 20
				last_path_ = @last_tool.last_path
				#VBO::ShapeForge.debug last_path_
				if last_path_
					Sketchup.active_model.active_path = last_path_
				end
			end
			@last_tool.reset
			@last_tool.state = "pick"
			@last_tool.selection = []
			@last_tool.member_path = nil
			Sketchup.active_model.tools.push_tool(@last_tool)
		end
		Sketchup.active_model.styles.selected_style = @last_style
		@is_editing = false
	end

	def self.enable_click_edit_ass_observer
		@click_edit_ass_ob = AssemMakerEditObserver.new
		Sketchup.active_model.add_observer(@click_edit_ass_ob)
	end
	def self.disable_click_edit_ass_observer
		if @click_edit_ass_ob
			Sketchup.active_model.remove_observer(@click_edit_ass_ob)
		end
	end

	class AssemMakerEditObserver < Sketchup::ModelObserver
		attr_accessor :last_path, :last_edit, :last_join
		def onActivePathChanged(model)
			path =  model.active_path.to_a
			assem =  VBO::ShapeForge::Identify.assembly?(path.to_a[-1])
			assem = VBO::ShapeForge::ForgeStructure.read(path.to_a[-1]) if assem

			if path.to_a != @last_path.to_a
				if @last_path && @last_edit && !@last_path.empty?
					assem =  VBO::ShapeForge::Identify.assembly?(@last_path.to_a[-1])
					if assem
						# VBO::ShapeForge.debug "jump out"
						assem = VBO::ShapeForge::ForgeStructure.read(@last_path.to_a[-1])
						@last_edit = false
						VBO::ShapeForge.finished_edit_assembly(assem)
						return
					end
				end
			end

			if path && assem && !@last_join  && !@last_edit
				@last_join = true
				if assem
					# VBO::ShapeForge.debug "jump in"
					VBO::ShapeForge.begin_edit_asembly(assem)
					@last_edit = true
				end
			else
				@last_join = false
			end
			@last_path = path
		end

		#def onTransactionStart(model)
		#    VBO::ShapeForge.debug "onTransactionStart: #{model}"
		#end
		def onTransactionUndo(model)
			VBO::ShapeForge.check_ass_undo(model)
		end
		def onTransactionRedo(model)
			VBO::ShapeForge.check_ass_redo(model)
		end
	end

	def self.begin_edit_asembly(assem)

		@last_style = Sketchup.active_model.styles.selected_style
		@is_editing = true
		Sketchup.active_model.styles.selected_style = edit_theme
		@last_tool = Sketchup.active_model.tools.active_tool if Sketchup.version.to_i.ceil >= 19
		Sketchup.active_model.select_tool nil
		path = Sketchup.active_model.active_path
		transformation = Sketchup.active_model.edit_transform
		@path_edit_entities = assem.entities
		#Sketchup.active_model.commit_operation
		@last_edit_trans = assem.to_path transformation
		#Sketchup.active_model.start_operation("jump", true)

		cpoint = @path_edit_entities.add_cpoint Geom::Point3d.new [0,0,0]

		enable_path_edit_entities_observer
	end

	def self.finished_edit_assembly(assem)
		# During undo/redo the underlying entities or group might have been deleted.
		begin
			entities = assem.entities
		rescue StandardError
			entities = nil
		end
		disable_path_edit_entities_observer

		return unless entities && entities.respond_to?(:grep)

		Sketchup.active_model.start_operation "Finish Edit Path", true, false, true
		trans = assem.transformation
		return unless trans # If group is deleted, skip
		g = VBO::ShapeForge::Graph.new(entities).transform!(trans)
		begin
			grp = assem.group
			grp.erase! if grp && grp.valid?
		rescue StandardError
			# ignore – group might already be gone
		end
		sg = g.create_graph_from_simplified_graph(g.simply_graph)
		longest_paths = sg.merge_edges_to_polylines(sg.edges)
		longest_paths.each{|edge|
			as = VBO::ShapeForge::ForgeStructure.add(Sketchup.active_model.active_entities)
			as.fence = assem.fence
			as.set_chain edge
			gc = as.draw
		}

		Sketchup.active_model.commit_operation
		if @last_tool && @last_tool.respond_to?(:last_path)
			if Sketchup.version.to_i.ceil >= 20
				last_path_ = @last_tool.last_path
				#VBO::ShapeForge.debug last_path_
				if last_path_
					Sketchup.active_model.active_path = last_path_
				end
			end
			@last_tool.reset
			@last_tool.state = "pick"
			@last_tool.selection = []
			@last_tool.member_path = nil
			Sketchup.active_model.tools.push_tool(@last_tool)
		end
		Sketchup.active_model.styles.selected_style = @last_style
		@is_editing = false
	end

	def self.enable_path_edit_entities_observer
		@path_edit_ob = ShapeForgeEntitiesObserver.new
		@path_edit_entities.add_observer(@path_edit_ob)
	end
	def self.disable_path_edit_entities_observer
		begin
			@path_edit_entities.remove_observer(@path_edit_ob) if @path_edit_ob && @path_edit_entities && @path_edit_entities.respond_to?(:remove_observer)
		rescue StandardError
			# entities might be deleted; ignore
		ensure
			@path_edit_ob = nil if @path_edit_ob
		end
	end

	def self.begin_edit_profile(group)
		# VBO::ShapeForge.debug "edit profile"
		@is_editing = true
		@last_style = Sketchup.active_model.styles.selected_style
		Sketchup.active_model.styles.selected_style = edit_theme("profile")
		@last_tool = Sketchup.active_model.tools.active_tool if Sketchup.version.to_i.ceil >= 19
		Sketchup.active_model.select_tool nil

		cam = Sketchup.active_model.active_view.camera
		@eye = cam.eye
		@target = cam.target
		@up = cam.up
		if @last_tool && @last_tool.member
			#Sketchup.active_model.active_view.zoom group.entities
		else
			temp_target = Geom::Point3d.new(0,0,0)
			temp_up = Geom::Vector3d.new(0,1,0)
			temp_eye = Geom::Point3d.new(0,0,10)
			cam.set(temp_eye,temp_target,temp_up)
			Sketchup.active_model.active_view.zoom Sketchup.active_model.active_entities
		end
	end

	def self.finished_edit_profile(group)
		# VBO::ShapeForge.debug "get out profile"
		profile = Shape.new(group)
		if @last_tool
			@last_tool.reset
			if @last_tool.member
				@last_tool.finished_edit_member_profile(profile)
			else
				@last_tool.temp_profile = profile
			end
			Sketchup.active_model.tools.push_tool(@last_tool)
		end
		group.erase!
		Sketchup.active_model.styles.selected_style = @last_style
		@is_editing = false
	end

	def self.enable_shapeforge_app_observer
		@ap_ob = ShapeForgeAppObserver.new
		Sketchup.add_observer(@ap_ob)
	end
	def self.disable_shapeforge_app_observer
		Sketchup.remove_observer(@ap_ob)
	end

	def self.enable_scale_tool_observer
		@scale_tool_ob = ShapeForgeToolObserver.new
		Sketchup.active_model.tools.add_observer(@scale_tool_ob)
	end

	def self.disable_scale_tool_observer
		Sketchup.active_model.tools.remove_observer(@scale_tool_ob)
	end

	def self.enable_click_edit_observer
		@click_edit_ob = ShapeForgeEditObserver.new
		Sketchup.active_model.add_observer(@click_edit_ob)
	end
	def self.disable_click_edit_observer
		if @click_edit_ob
			Sketchup.active_model.remove_observer(@click_edit_ob)
		end
	end

	def self.enable_dialog_undo_observer
		disable_dialog_undo_observer
		@dundo_ob = DialogModelObserver.new
		Sketchup.active_model.add_observer(@dundo_ob)
	end
	def self.disable_dialog_undo_observer
		if @dundo_ob
			Sketchup.active_model.remove_observer(@dundo_ob)
		end
	end
	# ProfilesMakerToolsObserver
	def self.enable_dialog_tool_observer
		disable_dialog_tool_observer
		@dtool_ob = ProfilesMakerToolsObserver.new
		Sketchup.active_model.tools.add_observer(@dtool_ob)
	end
	def self.disable_dialog_tool_observer
		if @dtool_ob
			Sketchup.active_model.tools.remove_observer(@dtool_ob)
		end
	end

	class ShapeForgeOverlay < Sketchup::Overlay
		attr_accessor :center
		attr_reader :shape, :position
		def initialize
			super('shapeforge_overlay', 'ShapeForge Overlay')
		end
		def shape=(shape)
			# puts "set shape: #{shape}"
			@shape = shape
			# @shape = shape
		end

		def draw(view)
			if @shape
				#  Options
				model = Sketchup.active_model
				options = model.rendering_options
				color_by_layer = options["DisplayColorByLayer"]

				background = options["BackgroundColor"]
				face_front = options["FaceFrontColor"]
				face_back = options["FaceBackColor"]

				edge_color = 'black'
				edge_width = options["SectionCutWidth"]
				box = @shape[:box]
				puts "box: #{box.width} x #{box.height} x #{box.depth}"
				# Drawings setup
				scale = 200.0 / @shape[:width]
				# tr2 = Geom::Transformation.scaling(@shape[:grid][6], scale)
				# tr = Geom::Transformation.translation(@shape[:grid][6].vector_to(Geom::Point3d.new(50,50,0)))

				tr2 = Geom::Transformation.scaling(@shape[:box].min, scale)
				tr = Geom::Transformation.translation(@shape[:box].min.vector_to(Geom::Point3d.new(50,50,0)))

				base_origin = @shape[:grid][4].transform(tr * tr2)
				section = @shape[:section].map{|lo|
					lo.map{|pt| pt.transform(tr * tr2)}
				}

				grid = @shape[:grid].map{|pt| pt.transform(tr * tr2)}

				# Fill Section
				mat_name = @shape[:shape].material_name
				if color_by_layer
					layer = model.layers[@shape[:shape].layer_name]
					puts "layer: #{layer}"
					color = layer ? layer.color : Sketchup::Color.new('white')
				else
					material = model.materials[@shape[:shape].material_name]
					if material
						if material.texture
							color = Sketchup::Color.new('black')
						else
							color = material.color
							color.alpha = material.alpha
						end
					else
						color = Sketchup::Color.new('white')
					end
				end
				view.line_width = 1
				view.drawing_color = color
				triangles = Geom.tesselate(*section)
				view.draw2d(GL_TRIANGLES, triangles)

				# Section Loops
				view.line_width = edge_width
				view.drawing_color = edge_color
				section.each{|lo|
					view.draw2d(GL_LINE_LOOP,lo)
				}

				view.line_width = 50
				view.drawing_color = 'blue'
				grid.each{|pt|
					DRAWVIEW.draw_point_2d(view, pt, 5, 'red')
				}
			else
				view.draw_text([10,10,0], "ShapeForge Overlay")
			end
		end
	end

	def self.enable_overlay
		# puts 'enable overlay'
		# ov = Sketchup.active_model.overlays.find { |o| o.overlay_id == 'shapeforge_overlay' }
		# if ov
		# 	ov.enabled = true
		# else
		# 	ov = ShapeForgeOverlay.new
		# 	Sketchup.active_model.overlays.add(ov)
		# 	ov.enabled = true
		# end
	end
	def self.disable_overlay
		# puts 'disable overlay'
		# ov = Sketchup.active_model.overlays.find { |o| o.overlay_id == 'shapeforge_overlay' }
		# if ov
		# 	ov.enabled = false
		# end
	end
end
