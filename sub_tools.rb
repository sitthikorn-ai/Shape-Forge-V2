require 'sketchup.rb'
Sketchup.require File.join(File.dirname(__FILE__), 'member')
Sketchup.require File.join(File.dirname(__FILE__), 'methods')
Sketchup.require File.join(File.dirname(__FILE__), 'drawview')
module VBO
	module ShapeForge
		class PTool
			def finished_edit_member_profile(profile)
				if @member
					Sketchup.active_model.start_operation("VBO ShapeForge - Apply Edited Shape", true)
					@member.set_from_profile!(profile)
					@temp_profile = profile
					Sketchup.active_model.commit_operation
				end
			end
			private
			def add_point_to_member_chain
				@temp_profile = @member.profile
				Sketchup.active_model.start_operation("ShapeForge - Add Point To Member Chain", true)
				transformation = Sketchup::InstancePath.new(@member_path).transformation
				cls = @member.chain.closest_point_on_chain(@pickray, transformation)
				point = cls[1].transform(@pick_transformation.inverse)
				index = cls[0] + 1
				chain_path = @member.chain.path
				chain_path.insert(index, point)
				@member.set_chain(chain_path)
				@member.draw
				profile = @member.profile
				profile.set_from_profile_member(@member)
				@member.set_from_profile!(profile, false)
				trim_after_draw(@member)
				Sketchup.active_model.commit_operation
			end

			def split_member_at_point
				@temp_profile = @member.profile
				Sketchup.active_model.start_operation("ShapeForge - Split Member At Point", true)
				transformation = Sketchup::InstancePath.new(@member_path).transformation
				@member.split_at_point(@pickray, "normal", transformation)
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
			end
			def start_new_member(view)
				@state = "click-click"
				@sub_click = "draw"
				view.lock_inference if view.inference_locked?
				trans = Sketchup::InstancePath.new(@member_path).transformation
				closet_point = @member.chain.closest_point_on_chain(@pickray, trans)
				point = closet_point[1].transform(trans.inverse)
				index = closet_point[0] + 1

				point = @closest_point if @closest_point
				@click_click_data = {
						point: point
					}
				@pts = [@click_click_data[:point], @click_click_data[:point]]
			end
			def remove_chain_point
				return if !@member || @index_adjust.nil?
				Sketchup.active_model.start_operation("ShapeForge - Remove Point", true)
				chain_path = @member.chain.path
				if [ @member.chain.length - 1, 0].include?(@index_adjust) && @member.closed_path?
					chain_path.delete_at(@member.chain.length - 1)
					chain_path.delete_at(0)
					chain_path << chain_path[0]
				else
					chain_path.delete_at(@index_adjust)
				end
				@member.set_chain(chain_path)
				@member.draw
				profile = @member.profile
				profile.set_from_profile_member(@member)
				@member.set_from_profile!(profile, false)
				trim_after_draw(@member)
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
			end

			def trim_after_draw(member, trans = Geom::Transformation.new)
				member.update_trim(trans)
			end

			def trim_member_to_plane(data, transformation, chain)
				face = @trim_objects[:face]
				return unless face
				Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member To Plane", true)
				cap_index = data[:start] ? 0 : 1
				hover_trans = Sketchup::InstancePath.new(@trim_objects[:path]).transformation
				plane = [face.vertices[0].position, face.normal].map{|c| c.transform(hover_trans)}
				data[:member].trim_to_plane(plane, cap_index, transformation)
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
				reset
			end
			def trim_member_to_solid(data, transformation, chain)
				solid = @trim_objects[:solid]
				if solid
					Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member To Solid", true)
					begin
						cap_index = data[:start] ? 0 : 1

						solid.pop until solid[-1].respond_to?(:definition)
						temp = solid[-1]
						solid.pop
						#puts "temp #{temp} - #{temp.parent.class} - memberpath #{data[:member_path][-1].parent.class}"
						if temp.parent != data[:member_path][-1].parent && !temp.parent.nil? && !data[:member_path][-1].parent.nil?
							trans = solid.length < 2 ?  Geom::Transformation.new : Sketchup::InstancePath.new(solid[0..-2]).transformation

							member_path = data[:member_path]
							member_path = nil if member_path.length < 2
							member_trans = member_path.nil? ? Geom::Transformation.new : Sketchup::InstancePath.new(member_path.to_a[0..-2]).transformation

							entities = member_path.nil? ? Sketchup.active_model.entities : member_path[-1].parent.entities

							ins = entities.add_instance(temp.definition,  (member_trans.inverse) * trans)
							ins.make_unique
							delete = true
						else
							ins = temp
							delete = false
						end
						data[:member].trim_to(ins, cap_index, data[:member_path], temp.persistent_id)
						ins.erase! if delete
					rescue=> error
						UI.messagebox(error)
						Sketchup.active_model.abort_operation
					end
					Sketchup.active_model.commit_operation
					reset
					VBO::ShapeForge.manager_need_reload
					@member_path[-1] = data[:member].instance
				end
			end
			def miter_joint_split
				Sketchup.active_model.start_operation("ShapeForge - Miter Joints Split", true)
				@member.draw('miter_joint')
				Sketchup.active_model.commit_operation
				@member = nil
				@member_path = nil
				reset
				VBO::ShapeForge.manager_need_reload
			end
			def extend_member(data, transformation, chain)
				Sketchup.active_model.start_operation("VBO ShapeForge - Extend Member", true)
				if data[:start]
					chain[0] = @pts[0].project_to_line(data[:line]).transform(transformation.inverse)
					cap = 0
				else
					chain[-1] = @pts[0].project_to_line(data[:line]).transform(transformation.inverse)
					cap = 1
				end
				data[:member].set_chain(chain)
				data[:member].delete_attribute("cap_#{cap}_trim")
				draw_mode = chain.length == 2 ? "continuous" : data[:member].profile.junction_style
				data[:member].draw(draw_mode)
				Sketchup.active_model.commit_operation
				Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member Cap", true)
				trim_after_draw(data[:member])
				@member_path[-1] = data[:member].instance if @member_path
				Sketchup.active_model.commit_operation
				reset
				@member_path[-1] = data[:member].instance if @member_path
				VBO::ShapeForge.manager_need_reload
			end
			def toggle_chain_closed(chain)
				Sketchup.active_model.start_operation("ShapeForge - Close/Open Chain", true)
				path = chain.path
				if chain.closed_path?
					path.pop
				else
					path << chain[0]
				end
				@member.set_chain path
				@member.draw
				Sketchup.active_model.commit_operation
				reset
				VBO::ShapeForge.manager_need_reload
			end
			def rename_member_profile
				result = UI.inputbox(["Shape Name: "],[@member.profile.name], "VBO Profiles Toy")
				if result
					Sketchup.active_model.start_operation("ShapeForge - Adjust Shape Name", true)
					profile = @member.profile
					profile.set_from_profile_member(@member)
					profile.name = result[0]
					@member.set_from_profile!(profile, false)
					Sketchup.active_model.commit_operation
				end
				VBO::ShapeForge.manager_need_reload
			end
			def save_member_profile
				skp = UI.savepanel("Save ProfileBuilder's Shape", "", "#{@temp_profile.name} - #{@temp_profile.width.to_l} x #{@temp_profile.height.to_l}.skp")
				@temp_profile.save_skp(skp) if skp
			end
			def load_member_profile
				skp = UI.openpanel("Load ProfileBuilder's Shape", "", "SketchUp Files|*.skp||")
				if skp
					@temp_profile = VBO::ShapeForge::Shape.new(skp)
					Sketchup.active_model.start_operation("ShapeForge - Apply Shape", true)
					@member.set_from_profile!(@temp_profile)
					Sketchup.active_model.commit_operation
				end
			end
			def rename_temp_profile
				result = UI.inputbox(["Shape Name: "],[@temp_profile.name], "VBO Profiles Toy")
				if result
					@temp_profile.name = result[0]
				end
			end
			def edit_temp_profile(view, x, y)
				ip1 = view.inputpoint x,y
				trans = Geom::Transformation.new(ip1.position)
				group = @temp_profile.to_group(trans)
				Sketchup.active_model.selection.clear
				Sketchup.active_model.selection.add group
				#if Sketchup.version.to_i.ceil >= 20
				#    Sketchup.active_model.active_path = Sketchup.#active_model.active_path.to_a + [group]
				#end
			end
			def save_temp_profile
				skp = UI.savepanel("Save ProfileBuilder's Shape", "", "#{@temp_profile.name} - #{@temp_profile.width.to_l} x #{@temp_profile.height.to_l}.skp")
				@temp_profile.save_skp(skp) if skp
			end
			def edit_member_profile(profile)
				transformation = Sketchup::InstancePath.new(@member_path).transformation
				i, point = @member.chain.closest_point_on_chain(@pickray, transformation)
				return if point.nil?
				#point = point.transform(transformation)
				vector = @member.chain[i].transform(transformation).vector_to(point)
				trans = Geom::Transformation.new(point, vector.reverse)
				group = profile.to_group(trans)
				Sketchup.active_model.selection.clear
				Sketchup.active_model.selection.add group
				#if Sketchup.version.to_i.ceil >= 20
				#    Sketchup.active_model.active_path = Sketchup.active_model.active_path.to_a + [group]
				#end
				VBO::ShapeForge.manager_need_reload
			end
			def mirror_member_profile
				Sketchup.active_model.start_operation("ShapeForge - Mirror Shape", true)
				@member.mirror!
				profile = @member.profile
				profile.set_from_profile_member(@member)
				@member.set_from_profile!(profile, true)
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
			end
			def mirror_temp_profile
				@temp_profile.mirror = !@temp_profile.mirror
			end
			def al
				["Top - Left", "Top - Midle", "Top - Right", "Midle - Left", "Center", "Midle - Right", "Bottom - Left", "Bottom - Midle", "Bottom - Right"]
			end
			def set_member_profile_alignment
				result = UI.inputbox(["Shape's Alignment:"],[al[@member.placement_point.to_i - 1]],[al.join('|')], "VBO Profiles Toy")
				if result
					Sketchup.active_model.start_operation("ShapeForge - Shape Alignment", true)
					@member.placement_point = al.index(result[0]) + 1
					profile = @member.profile
					profile.set_from_profile_member(@member)
					@member.set_from_profile!(profile, true)
					Sketchup.active_model.commit_operation
					VBO::ShapeForge.manager_need_reload
				end
			end
			def set_temp_profile_alignment
				result = UI.inputbox(["Shape's Alignment:"],[al[@temp_profile.placement_point.to_i - 1]],[al.join('|')], "VBO Profiles Toy")
				if result
					@temp_profile.placement_point = al.index(result[0]) + 1
				end
			end
			def member_profile_rotation
				result = UI.inputbox(["Rotation in degrees"],[@member.rotation], "VBO Profiles Toy")
				if result
					Sketchup.active_model.start_operation("ShapeForge - Shape Rotation", true)
					@member.rotation = result[0].to_f
					profile = @member.profile
					profile.set_from_profile_member(@member)
					@member.set_from_profile!(profile, true)
					Sketchup.active_model.commit_operation
					VBO::ShapeForge.manager_need_reload
				end
			end
			def temp_profile_rotation
				result = UI.inputbox(["Rotation in degrees"],[@temp_profile.rotation], "VBO Profiles Toy")
				if result
					@temp_profile.rotation = result[0].to_f
				end
			end
			def member_profile_width
				result = UI.inputbox(["Width: "],[@member.profile.width.to_l], "VBO Profiles Toy")
				if result
					Sketchup.active_model.start_operation("ShapeForge - Adjust Shape Width", true)
					profile = @member.profile
					profile.set_from_profile_member(@member)
					width = profile.default_width
					profile.set_from_profile_member(@member)
					profile.x_scale = result[0].to_l.to_f / width
					@member.set_from_profile!(profile)
					Sketchup.active_model.commit_operation
					VBO::ShapeForge.manager_need_reload
				end
			end
			def temp_profile_width
				result = UI.inputbox(["Width: "],[@temp_profile.profile.width.to_l], "VBO Profiles Toy")
				if result
					width = @temp_profile.default_width
					@temp_profile.x_scale = result[0].to_l.to_f / width
				end
			end
			def member_profile_height
				result = UI.inputbox(["Height: "],[@member.profile.height.to_l], "VBO Profiles Toy")
				if result
					Sketchup.active_model.start_operation("ShapeForge - Adjust Shape Height", true)
					profile = @member.profile
					profile.set_from_profile_member(@member)
					height = profile.default_height
					profile.set_from_profile_member(@member)
					profile.y_scale = result[0].to_l.to_f / height
					@member.set_from_profile!(profile)
					Sketchup.active_model.commit_operation
					VBO::ShapeForge.manager_need_reload
				end
			end

			def temp_profile_height
				result = UI.inputbox(["Height: "],[@member.profile.height.to_l], "VBO Profiles Toy")
				if result
					height = @temp_profile.default_height
					@temp_profile.y_scale = result[0].to_l.to_f / height
				end
			end
			def reverse_member
				Sketchup.active_model.start_operation("ShapeForge - Reverse Member", true)
				profile = @member.profile
				profile.set_from_profile_member(@member)
				@member.reverse
				profile.set_from_profile_member(@member)
				@member.set_from_profile!(profile, false)
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
			end
			def delete_member
				Sketchup.active_model.start_operation("ShapeForge -Delete Member")
				@member_path[-1].erase!
				@member_path = nil
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
			end
			def append_profile
				Sketchup.active_model.start_operation("ShapeForge -Append Shape")
				 transformation =  @pick_transformation
				chain = @member.chain.path.map{|c| c.transform(transformation )}
				pm = VBO::ShapeForge::ForgeElement.add(Sketchup.active_model.active_entities, chain)
				pm.set_from_profile!(@temp_profile)
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
			end
			def reset_cap
				cap_index = @index_adjust == 0 ? 0 : 1
				Sketchup.active_model.start_operation("ShapeForge -Reset Cap", false)
				@member.delete_attribute("cap_#{cap_index}_trim")
				@member.draw
				Sketchup.active_model.commit_operation
				Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member Cap", true)
				trim_after_draw(@member)
				Sketchup.active_model.commit_operation
			end
			def split_at_point(type)
				Sketchup.active_model.start_operation("ShapeForge -Split Member", true)
				if @member_path.length > 2
					parent_path = @member_path[0..@member_path.length - 2]
					transformation = Sketchup::InstancePath.new(parent_path).transformation
				else
					parent_path = []
					transformation = Geom::Transformation.new
				end
				a,b = @member.split_at_junction(@index_adjust, type, transformation)
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
			end

		end

	end
end
