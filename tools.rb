require 'sketchup.rb'
Sketchup.require File.join(File.dirname(__FILE__), 'member')
Sketchup.require File.join(File.dirname(__FILE__), 'methods')
Sketchup.require File.join(File.dirname(__FILE__), 'drawview')
Sketchup.require File.join(File.dirname(__FILE__), 'sub_tools')
module VBO
	module ShapeForge
		class PTool
			attr_accessor :temp_profile, :member, :pos, :last_path, :state, :selection, :member_path, :state
			attr_reader :cursor_id, :cursors
			include Geometry

			def initialize
				@auto_grab_member = nil
				sel = Sketchup.active_model.selection.to_a
				sel.each do |ent|
					if VBO::ShapeForge::Identify.profile_member?(ent)
						@auto_grab_member = ent
						break
					end
				end

				if @auto_grab_member.nil?
					Sketchup.active_model.selection.clear
				else
					active_path = Sketchup.active_model.active_path ? Sketchup.active_model.active_path.to_a : []
					@selection = [active_path + [@auto_grab_member]]
				end

				@ip  = nil
				@ip1 = nil
				@ip2 = nil
				@pts = []
				@cls = []

				@member_color = Sketchup::Color.new('brown')
				@branch_color = nil#Sketchup::Color.new('magenta')
				@chain_color = Sketchup::Color.new("magenta")
				@profile_color = Sketchup::Color.new('green')
				@face_color = Sketchup::Color.new("magenta")
				@edge_color = Sketchup::Color.new("magenta")
				@selection_color = Sketchup::Color.new('brown')
				@selection = [] if @selection.nil?
				@cpoints = []
				#@junctions_style = VBO::ShapeForge.load_last_junctions_style


				@state = "pick"
				@temp_profile = if VBO::ShapeForge.profile_dialog_visible? && VBO::ShapeForge.profile_dialog.temp_profile
					VBO::ShapeForge.profile_dialog.temp_profile
				else
					VBO::ShapeForge.load_last_profile
				end


				path_to_images = File.join(File.dirname(__FILE__), 'images/cursors')
				#puts path_to_images
				@cursors = {}
				po = {
					"apply" => [0, 36],
					"get_definition" => [0, 36],
					"get_layer" => [0, 36],
					"get_material" => [0, 36],
					"get" => [0, 36],
					"hold" => [4,4],
					"move" => [12,12],
					"pencil" => [0, 24],
					"select" => [0,0],
					"trim-plane" => [0,12],
					"trim-solid" => [0,12],

				}
				Dir[File.join(path_to_images,"*.*")].each{|c|
					d = File.basename(c).split('.')[0]
					@cursors[d] = UI.create_cursor(c, po[d][0],po[d][1])
				}
			end

			def activate
				@ip  = Sketchup::InputPoint.new
				@ip1 = Sketchup::InputPoint.new
				@ip2 = Sketchup::InputPoint.new
				if VBO::ShapeForge.profile_dialog_visible?
					VBO::ShapeForge.profile_dialog.temp_profile = @temp_profile
					VBO::ShapeForge.profile_dialog.temp_profile.preview(VBO::ShapeForge.profile_dialog.dialog)
				end
			end

			def getExtents
				box=Sketchup.active_model.bounds
				box.add(@ip1.position) if @ip1.valid?
				box.add(@ip2.position) if @ip2.valid?
				box.add(@pts[1]) if @pts && @pts[1]
				box
			end

			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
				#Sketchup.active_model.active_view.invalidate
			end

			def onCancel(reason, view)
				@trim_objects = nil
				case reason
				when 0 #Esc key
					case @state
					when "pick"
						@selection = []
						@cpoints.each{|c| c.erase!}
						@cpoints = []
					when "click-click"
						reset
						case @sub_click
						when "extend"
						when "draw"
						when "moving"
						when "adjust"
						when "append"
						end
					end
				when 2 #Undo
					reset
				end
			end

			def change_cursor(name)
				@cursor_id = @cursors[name]
			end

			def reset(state = @state)
				@ip1.clear
				@cpoints.each{|c| c.erase!}
				@cpoints = []
				@auto_snap_point = nil
				@auto_snap_index = nil
				@auto_snap_axis = nil
				@auto_snap_axis_vec = nil
				case state
				when "pick"
					@state = "pick"
				when "click-click"
					@pts = []
					@path = nil
					@state = "pick"
				end
			end

			def deactivate(view)
				view.invalidate
				#Sketchup.write_default("VBO ShapeForge", "LastProfile", @temp_profile.to_s)
				@cpoints.each{|c| c.erase!}
				@cpoints = []
				VBO::ShapeForge.save_last_profile(@temp_profile)
				if VBO::ShapeForge.profile_dialog_visible?
					VBO::ShapeForge.profile_dialog.uncheck('settings|magic')
					if !Options.new.pinned
						VBO::ShapeForge.profile_dialog.run_script('clearCanvas();')
					end
				end
				#VBO::ShapeForge.save_last_junctions_style(@last_junctions_style)
			end

			def draw(view)
				draw_selection(view)
				case @state
				when "pick"
					return if @pos.nil?
					# Draw auto-snap preview dot when cursor is near an endpoint
					if @auto_snap_point
						view.draw_points([@auto_snap_point], 15 * UI.scale_factor, 2, Sketchup::Color.new('red'))
						# Draw axis direction line preview
						if @auto_snap_axis_vec
							axis_color = case @auto_snap_axis
							when :x then Sketchup::Color.new('red')
							when :y then Sketchup::Color.new('green')
							when :z then Sketchup::Color.new('blue')
							else Sketchup::Color.new('magenta')
							end
							view.line_width = 2
							view.line_stipple = "."
							view.drawing_color = axis_color
							line_len = 500
							vec_copy = @auto_snap_axis_vec.clone
							vec_copy.length = line_len
							p1 = @auto_snap_point.offset(vec_copy)
							p2 = @auto_snap_point.offset(vec_copy.reverse)
							view.draw(GL_LINES, [p1, p2])
							view.line_stipple = ""
						end
						change_cursor("hold")
						onSetCursor
						Sketchup.set_status_text "Click to start stretching"
						# Also draw the bounding box
						if @auto_grab_member && @auto_grab_member.respond_to?(:definition)
							face_color = Sketchup::Color.new('red')
							active_path = Sketchup.active_model.active_path ? Sketchup.active_model.active_path.to_a : []
							VBO::ShapeForge::DRAWVIEW.draw_instance_ref(active_path + [@auto_grab_member], face_color, view, true)
						end
					elsif @member_path
						case @pos[0]
						when 0
							if @closest_point || @pos[2]
								change_cursor("hold")
								onSetCursor
								Sketchup.set_status_text "Click to adjust member's point"
							else
								if @temp_profile != @member.profile
									change_cursor("get")
									onSetCursor
									#view.tooltip = "Get Shape: #{@member.profile.name}"
									Sketchup.set_status_text "Get Shape: #{@member.profile.fullname}"
								else
									change_cursor("select")
									onSetCursor
								end
								
								# Highlight Bounding Box (Transparent Red)
								if @member_path[-1].respond_to?(:definition)
									face_color = Sketchup::Color.new('red')
									VBO::ShapeForge::DRAWVIEW.draw_instance_ref(@member_path, face_color, view, true)
								end
							end

						when 4
							if @temp_profile != @member.profile

								change_cursor("apply")
								#onSetCursor
								draw_profile_3d(view, @selection_color) #if @member.chain.length < 10
							end
						when 12
							if @closest_point || @pos[2]
								change_cursor("pencil")
								onSetCursor
								draw_profile_3d(view, @selection_color)
							else
								change_cursor("select")
								onSetCursor
							end
						end

						if @closest_point || @pos[2]
						else
							if @temp_profile == @member.profile
								if @selection.include?(@member_path)
									Sketchup.set_status_text("Click to Un-isolate Member. Ins Key: Add Point to Member's chain")
								else
									Sketchup.set_status_text("Click to isolate Member. Ins Key: Add Point to Member's chain")
								end
							else
							end
						end
						draw_member(view) if !@face && !@edge && (@selection.include?(@member_path) || @selection.empty?)
					else
						change_cursor("pencil")
						#onSetCursor
						@ip1.draw(view) if @ip1.valid?
						Sketchup.set_status_text "Click to set first point of a new member"
					end
					case @pos[0]
					when 0
					when 8
						if @face
							if @temp_profile
								#view.tooltip = "Click to apply \"#{@temp_profile.name}\" to face's outerloop"
								Sketchup.set_status_text "Click to apply \"#{@temp_profile.fullname}\" to face's outerloop. Shift - Click to create new profile from face."
							else
								Sketchup.set_status_text "Shift - Click to create new profile from face."
							end
							draw_picked_face(view, @face_color, true)
						end
						if @edge
							if @temp_profile
								#view.tooltip =  "Click to apply \"#{@temp_profile.name}\" to edge."
								Sketchup.set_status_text "Click to apply \"#{@temp_profile.name}\" to edge. Shift - Click to apply \"#{@temp_profile.fullname}\" to best path from this edge."
							else
								Sketchup.set_status_text("Hold Shift key to see best path from this edge.")
							end
							draw_picked_edge(view, @edge.vertices)
						end
					when 4
						if @face
							change_cursor("get")
							onSetCursor
							view.tooltip =  "Click to create new profile from face."
							draw_picked_face(view, @selection_color)
						end
						if @edge
							view.tooltip =  "Click to apply \"#{@temp_profile.fullname}\" to best path from this edge." if @temp_profile
							best_path = VBO::ShapeForge.best_path_from_edge(@edge, @pos[0] == 12)
							draw_picked_edge(view, best_path)
						end
					end
				when "click-click"

					@ip1.draw(view) if @ip1.valid? && @ip1 != @pts[1] && @ip1.display?
					@ip2.draw(view) if @ip2.valid? && @ip1 != @pts[1] && @ip2.display? && !@closest_point
					case @sub_click
					when "moving", "append", "adjust"
						draw_member(view, nil, nil, @sub_click == "adjust") if @member_path
						draw_extend(view)  if @pts

						if @sub_click == "append"
							change_cursor("pencil")
							onSetCursor
						else
							change_cursor("move")
							onSetCursor
						end

					when "extend"

						draw_member(view) if @member_path
						draw_extend(view)  if @pts
						if @trim_objects
							case @trim_objects[:pos][0]
							when 4 #shift hover
								if @trim_objects[:face]
									VBO::ShapeForge::DRAWVIEW.draw_face(@trim_objects[:path], @face_color, view)
									change_cursor("trim-plane")
								end
							when 8 #ctrl hover
								if @trim_objects[:solid]
									VBO::ShapeForge::DRAWVIEW.draw_instance_ref(@trim_objects[:solid], @face_color, view)
									change_cursor("trim-solid")
								end
							else
								change_cursor("pencil")
							end
							onSetCursor
						else
							change_cursor("move")
							onSetCursor
						end
					when "draw"
						change_cursor("pencil")
						onSetCursor
						draw_extend(view)  if @pts
					end
				end
			end

			def onMouseMove(flags, x, y, view)
				case @state
				when "click-click"
					@ip.pick view, x, y, @ip1
					view.tooltip = @ip.tooltip if( @ip.valid? )
					@pts[0] = @ip.position
					@ip2.copy! @ip
					view.invalidate

					data = @click_click_data
					if Sketchup.active_model.active_path
						ip1 = view.inputpoint x,y
						edge = ip1.edge
						face = ip1.face
						path = nil
						path =  ip1.instance_path.to_a if edge
						path =  ip1.instance_path.to_a if face
					else
						ph = view.pick_helper
						ph.do_pick(x, y)
						path = ph.path_at(0)
						path[-1] = path[-1].edges[0] if path && path[-1].is_a?(Sketchup::Vertex)
					end
					if path
						pick_transformation = Sketchup::InstancePath.new(path).transformation
						active_transformation = Sketchup.active_model.edit_transform.inverse

						transformation = active_transformation * pick_transformation
						i = path.to_a.index{|c| VBO::ShapeForge::Identify.profile_member?(c)}
						member_path = i.nil? ? nil : path.slice(0, i + 1)
						if member_path
							member = VBO::ShapeForge::ForgeElement.new(member_path[-1])
							chain = member.chain.path.map{|c| c.transform(transformation)}
							index_adjust = chain.find_index{|c| view.screen_coords(c).distance([x,y,0]) < 20 * UI.scale_factor}
							@closest_point = index_adjust.nil? ? nil : chain[index_adjust]
							i = path.index{|c| c.respond_to?(:definition) && c.manifold?}
							solid = i.nil? || member.profile.is_1d? ? nil : path.slice(0, i + 1)
							#solid = (path[-2].respond_to?(:definition) && path[-2].manifold?  && path[-2].parent == member.instance.parent) ? path[0..-2] : nil
							pickray = view.pickray(x,y)
							@cls = member.chain.closest_point_on_chain(pickray, transformation)
						else
							index = path.index{|c|
								c.respond_to?(:manifold?) && c.manifold?
							}
							solid = path[0..index] if index
							@closest_point = nil
						end
					else
						@closest_point = nil
					end

					case @sub_click
					when "extend"
						vector = @pts[1].vector_to(@pts[0].project_to_line(data[:line]))
						length = vector.length
						length *= -1 if length != 0 && !vector.samedirection?(data[:vector])
						@trim_objects  = {
							path: path,
							pos: [flags, [x,y]],
							solid:  solid,
							face: path.nil? ? nil : path.find{|c| c.is_a?(Sketchup::Face) && vector.length!= 0 && !c.normal.transform(transformation).perpendicular?(vector)}
						}
						@trim_objects = nil if @trim_objects[:face].nil? && @trim_objects[:solid].nil? || flags == 0
						#puts @trim_objects.to_s
					when "moving", "append", "adjust", "draw"
						vector = @pts[1].vector_to(@pts[0])
						length = vector.length
					end

					Sketchup::set_status_text(length.to_l, SB_VCB_VALUE)
					if @closest_point
						if view.inference_locked?
							@ip2 = Sketchup::InputPoint.new(@closest_point)
							#view.lock_inference @ip1, @ip2
							#@pts[0] = @closest_point
						else
							@pts[0] = @closest_point
						end
						view.tooltip = "Point on Member's Chain"
					else
						view.tooltip = @ip2.tooltip
					end
					view.invalidate
				when "pick"
					if @auto_grab_member
						member_path = @selection[0]
						member = VBO::ShapeForge::ForgeElement.new(member_path[-1])
						transformation = Sketchup::InstancePath.new(member_path).transformation
						chain = member.chain.path.map{|c| c.transform(transformation)}

						d1 = view.screen_coords(chain[0]).distance([x, y, 0])
						d2 = view.screen_coords(chain[-1]).distance([x, y, 0])
						if [d1, d2].min < 30 * UI.scale_factor
							# Store snap preview data — do NOT enter moving yet
							@auto_snap_point = d1 < d2 ? chain[0] : chain[-1]
							@auto_snap_index = d1 < d2 ? 0 : 1
							@auto_snap_chain = chain
							@auto_snap_member = member
							@auto_snap_member_path = member_path
							@auto_snap_transformation = transformation
							# Determine dominant axis from member direction
							member_vec = chain[0].vector_to(chain[-1])
							if member_vec.length > 0
								ax = member_vec.dot(X_AXIS).abs
								ay = member_vec.dot(Y_AXIS).abs
								az = member_vec.dot(Z_AXIS).abs
								if az >= ax && az >= ay
									@auto_snap_axis = :z
									@auto_snap_axis_vec = Z_AXIS
								elsif ax >= ay
									@auto_snap_axis = :x
									@auto_snap_axis_vec = X_AXIS
								else
									@auto_snap_axis = :y
									@auto_snap_axis_vec = Y_AXIS
								end
							else
								@auto_snap_axis = nil
								@auto_snap_axis_vec = nil
							end
						else
							@auto_snap_point = nil
							@auto_snap_index = nil
							@auto_snap_axis = nil
							@auto_snap_axis_vec = nil
						end
						view.invalidate
						return
					end

					@ip.pick view, x, y
					if( @ip != @ip1 )
						@ip1.copy! @ip
					end
					view.lock_inference if view.inference_locked?
					@path, @member_path, @member, @pos, @pickray, @pick_transformation, @active_transformation, @face, @edge, @closest_point, @index_adjust = set_on_mouse_move_data(flags, x, y, view)
					transformation = @pick_transformation
					view.tooltip = @member.profile.fullname if @member
					#puts @member.chain.closest_point_on_path(@pickray, transformation).to_s if @member
					view.invalidate
				end
			end



			def onLButtonUp(flags, x, y, view)
				case @state
				when "pick"
					# Handle click on auto-snap point (from pre-selected member)
					if @auto_snap_point && @auto_grab_member
						@member = @auto_snap_member
						@member_path = @auto_snap_member_path
						@pick_transformation = @auto_snap_transformation
						@active_transformation = Sketchup.active_model.edit_transform.inverse
						@closest_point = @auto_snap_point
						@pos = [0, [x,y], @auto_snap_index]
						@index_adjust = @auto_snap_index == 0 ? 0 : @auto_snap_chain.length - 1

						@state = "click-click"
						@sub_click = "moving"
						view.lock_inference if view.inference_locked?
						set_click_click_data

						# Lock inference to the member's dominant axis
						if @auto_snap_axis_vec
							p1_lock = @auto_snap_point
							p2_lock = @auto_snap_point.offset(@auto_snap_axis_vec)
							ip_lock1 = Sketchup::InputPoint.new(p1_lock)
							ip_lock2 = Sketchup::InputPoint.new(p2_lock)
							view.lock_inference(ip_lock2, ip_lock1)
						end

						@auto_grab_member = nil
						@auto_snap_point = nil
						@auto_snap_index = nil
						@auto_snap_axis = nil
						@auto_snap_axis_vec = nil

						@ip2.pick(view, x, y)
						@pts[1] = @ip2.position if @ip2.valid?
						onMouseMove(flags, x, y, view)
						return
					end
					if @member_path
						pm = VBO::ShapeForge::ForgeElement.new(@member_path[-1])
						chain = pm.chain
						if (@pos[2] || (@closest_point && [chain[0], chain[-1]].include?(@closest_point))) && chain[0] != chain[-1]#click on a member's cap: extend or append
							case flags
							when 0
								if @selection.include?(@member_path)
									@state = "click-click"
									@sub_click = "moving"
									view.lock_inference if view.inference_locked?
									set_click_click_data
								else
									@selection = []
									@state = "click-click"
									@sub_click = "moving"
									view.lock_inference if view.inference_locked?
									set_click_click_data
								end
							end
						elsif @closest_point #click on a member's junction
							 transformation =  @pick_transformation
							chain = @member.chain.path.map{|c| c.transform(transformation)}
							@state = "click-click"
							if [chain[0], chain[-1]].include?(@closest_point)
								if chain[0] == chain[-1]
									@sub_click = case flags
									when 0
										"adjust"
									when 12, 8
										"draw"
									end
								else
									@sub_click = case flags
									when 0
										"moving"
									when 12, 8
										"draw"
									end
								end
							else
								@sub_click = case flags
								when 0
									"adjust"
								when 12, 8
									"draw"
								end
							end
							view.lock_inference if view.inference_locked?
							set_click_click_data
						else
							case flags
							when 4
								if @temp_profile
									if @temp_profile != @member.profile
										Sketchup.active_model.start_operation("ShapeForge - Apply Shape", true)
										 @member.set_from_profile!(@temp_profile)
										Sketchup.active_model.commit_operation
									else

									end
								end

							when 12

							when 0
								if @temp_profile != @member.profile
									@temp_profile = @member.profile
									@temp_profile.set_from_profile_member(@member)
									if VBO::ShapeForge.profile_dialog_visible?
										VBO::ShapeForge.profile_dialog.temp_profile = @temp_profile
										VBO::ShapeForge.profile_dialog.temp_profile.preview(VBO::ShapeForge.profile_dialog.dialog)
									end
								else
									if !@selection.include? @member_path
										@selection  = [@member_path]
									else
										@selection.delete_if{|c| c ==  @member_path}
									end
								end
							end
						end
					else
						@selection = []
					end
					if @edge
						if @temp_profile
							case flags
							when 0
								@state = "click-click"
								@sub_click = "draw"
								view.lock_inference if view.inference_locked?
								set_click_click_data
							when 8
								Sketchup.active_model.start_operation("ShapeForge -Apply Shape")
								 transformation =  @pick_transformation
								chain = @edge.vertices.map{|c| c.position.transform(transformation )}
								pm = VBO::ShapeForge::ForgeElement.add(Sketchup.active_model.active_entities, chain)
								pm.set_from_profile!(@temp_profile)
								Sketchup.active_model.commit_operation
								VBO::ShapeForge.manager_need_reload
								reset
								@member = pm
								@member_path = Sketchup.active_model.active_path.to_a + [@member.instance]
								@pick_transformation = Sketchup::InstancePath.new(@member_path).transformation
								@active_transformation = Sketchup.active_model.edit_transform.inverse
								@pos = [nil, nil, 1]
								@state = "click-click"
								@sub_click = "append"
								set_click_click_data
							when 4
								Sketchup.active_model.start_operation("ShapeForge -Apply Shape")
								 transformation =  @pick_transformation
								chain = VBO::ShapeForge.best_path_from_edge(@edge, flags == 12).map{|c| c.position.transform(transformation )}
								pm = VBO::ShapeForge::ForgeElement.add(Sketchup.active_model.active_entities, chain)
								pm.set_from_profile!(@temp_profile)
								Sketchup.active_model.commit_operation
								VBO::ShapeForge.manager_need_reload
								reset
								@member = pm
								@member_path = Sketchup.active_model.active_path.to_a + [@member.instance]
								@pick_transformation = Sketchup::InstancePath.new(@member_path).transformation
								@active_transformation = Sketchup.active_model.edit_transform.inverse
								@pos = [nil, nil, 1]
								@state = "click-click"
								@sub_click = "append"
								set_click_click_data
							end
						end
					end
					if @face
						case flags
						when 0
							@state = "click-click"
							@sub_click = "draw"
							view.lock_inference if view.inference_locked?
							set_click_click_data
						when 8
							if @temp_profile
								Sketchup.active_model.start_operation("ShapeForge -Apply Shape")
								 transformation =  @pick_transformation
								chain = @face.outer_loop.vertices.map{|c| c.position.transform(transformation )}
								chain << chain[0]
								pm = VBO::ShapeForge::ForgeElement.add(Sketchup.active_model.active_entities, chain)
								pm.set_from_profile!(@temp_profile)
								Sketchup.active_model.commit_operation
							end
						when 4
							@temp_profile = VBO::ShapeForge::Shape.new(@face)
							if VBO::ShapeForge.profile_dialog_visible?
								VBO::ShapeForge.profile_dialog.temp_profile = @temp_profile
								VBO::ShapeForge.profile_dialog.temp_profile.preview(VBO::ShapeForge.profile_dialog.dialog)
							end
						end
					end
					if @path.nil? && @selection.empty?
						if @temp_profile.nil?
							@temp_profile = VBO::ShapeForge.load_last_profile
							return if @temp_profile.nil?
						end
						@state = "click-click"
						@sub_click = "draw"
						view.lock_inference if view.inference_locked?
						set_click_click_data
					end
				when "click-click"
					@ip2.pick view, x, y, @ip1
					ph = view.pick_helper
					ph.do_pick(x, y)
					@path = ph.path_at(0)
					if @closest_point
						if view.inference_locked?
						else
						end
						@pts << @closest_point
					else
						@pts << @ip2.position
					end
					case @sub_click
					when "extend"
						do_extend if @pts.length > 2
					when "moving"
						do_moving if @pts.length > 2
					when "append"
						do_append if @pts.length > 2
					when "adjust"
						do_adjust if @pts.length > 2
					when "draw"
						do_draw_member if @pts.length > 2
					end
				end
				view.invalidate
			end

			def onLButtonDoubleClick(flags, x, y, view)
				if @member_path
					case @pos[2]
					when 0,1
						#puts flags
						@state = "click-click"
						@sub_click = "extend"
						set_click_click_data
						do_extend if flags != 1
					#when 1
					else
						if Sketchup.version.to_i.ceil >= 20
							#@last_path = Sketchup.active_model.active_path.to_a
							#Sketchup.active_model.start_operation("jump", true)
							#Sketchup.active_model.active_path = @member_path
							#Sketchup.active_model.commit_operation
						end
					end
				end
			end

			def onKeyDown(key, rpt, flags, view)
				case @state
				when "pick"
					case key
					when 16
						if @member_path && @temp_profile != @member.profile
							change_cursor("apply")
							onSetCursor
						elsif @face
							#change_cursor("get")
							#onSetCursor
						end
					end
				when "click-click"
					case @sub_click
					when "extend"
						case key
						when 9 #Tab key
							@sub_click = "moving"
							set_click_click_data
						when 17 #Ctrl key
							#@sub_click = "append"
						end
					when "moving", "append", "draw"
						case key
						when 17
							@sub_click = @sub_click == "append" ? "moving" : "append"
							set_click_click_data
						when 9
							@sub_click = "extend" if @sub_click != "draw"
							set_click_click_data
						when CONSTRAIN_MODIFIER_KEY
							@shift_down_time = Time.now
							if( view.inference_locked? )
								view.lock_inference
							elsif @ip2.valid? && @pts[0] != @pts[1]
								view.lock_inference @ip2, @ip1
							else
								view.lock_inference @ip1
							end
						when VK_LEFT
							@left_down = !@left_down
							if @left_down
								lock_axis(view,Y_AXIS)
							else
								view.lock_inference if view.inference_locked?
							end
							@right_down = @up_down = @down_down = false
						when VK_RIGHT
							@right_down = !@right_down
							if @right_down
								lock_axis(view,X_AXIS)
							else
								view.lock_inference if view.inference_locked?
							end
							@left_down = @down_down = @up_down = false
						when VK_UP
							@up_down = !@up_down
							if @up_down
								lock_axis(view,Z_AXIS)
							else
								view.lock_inference if view.inference_locked?
							end
							@down_down = @left_down = @right_down = false
						end
					when "adjust"
						case key
						when VK_DELETE, 8
						when 17
							#puts @click_click_data
							if @click_click_data[:start] || @click_click_data[:end]
								@sub_click = "moving"
								set_click_click_data
							end
						when 9
							if @click_click_data[:start] || @click_click_data[:end]
								@sub_click = "extend"
								set_click_click_data
							end
						when CONSTRAIN_MODIFIER_KEY
							@shift_down_time = Time.now
							if( view.inference_locked? )
								view.lock_inference
							elsif @ip2.valid? && @pts[0] != @pts[1]
								view.lock_inference @ip2, @ip1
							else
								view.lock_inference @ip1
							end
						when VK_LEFT
							@left_down = !@left_down
							if @left_down
								lock_axis(view,Y_AXIS)
							else
								view.lock_inference if view.inference_locked?
							end
							@right_down = @up_down = @down_down = false
						when VK_RIGHT
							@right_down = !@right_down
							if @right_down
								lock_axis(view,X_AXIS)
							else
								view.lock_inference if view.inference_locked?
							end
							@left_down = @down_down = @up_down = false

						when VK_UP
							@up_down = !@up_down
							if @up_down
								lock_axis(view,Z_AXIS)
							else
								view.lock_inference if view.inference_locked?
							end
							@down_down = @left_down = @right_down = false
						end
					end
				end
				view.invalidate
				#onMouseMove(@pos[0],*@pos[1], view)
			end

			def onKeyUp(key, rpt, flags, view)
				case @state
				when "pick"
					case key
					when 16

					when 45 #insert key
						add_point_to_member_chain
					when 46 #delete key
						remove_chain_point
					end
				when "click-click"
					case @sub_click
					when "adjust","moving","draw","append"
						if( key == CONSTRAIN_MODIFIER_KEY &&
							view.inference_locked? &&
							(Time.now - @shift_down_time) > 0.5 )
							view.lock_inference
						end
				  end
				end
				#puts key
				case key
				when 36 #home key
					if @member_path && @temp_profile == @member.profile
						Sketchup.active_model.start_operation("ShapeForge - Shape Alignment", true)
						if @member.placement_point > 1
							@member.placement_point -= 1
						else
							@member.placement_point = 9
						end
						profile = @member.profile
						profile.set_from_profile_member(@member)
						@member.set_from_profile!(profile, false)
						Sketchup.active_model.commit_operation
					else
						@temp_profile.placement_point -= 1
						@temp_profile.placement_point = 9 if @temp_profile.placement_point == 0
					end
				when 35 #end key
					if @member_path && @temp_profile == @member.profile
						Sketchup.active_model.start_operation("ShapeForge - Shape Alignment", true)
						if @member.placement_point < 9
							@member.placement_point += 1
						else
							@member.placement_point = 1
						end
						profile = @member.profile
						profile.set_from_profile_member(@member)
						@member.set_from_profile!(profile, false)
						Sketchup.active_model.commit_operation
					else
						@temp_profile.placement_point += 1
						@temp_profile.placement_point = 1 if @temp_profile.placement_point == 10
					end
				when 40
					if @member_path && @temp_profile == @member.profile
						Sketchup.active_model.start_operation("ShapeForge - Mirror Shape", true)
						@member.mirror!
						profile = @member.profile
						profile.set_from_profile_member(@member)
						@member.set_from_profile!(profile, false)
						Sketchup.active_model.commit_operation
					else
						@temp_profile.x_scale = - @temp_profile.x_scale if @temp_profile
					end
				when 8
					case @state
					when "pick"
					when "click-click"
						#reset
						case @sub_click
						when "extend"
							reset
						when "draw"
							reset
						when "moving"
							reset
						when "adjust"
							reset
						when "append"
							data = @click_click_data
							pm = ForgeElement.new(data[:member_path][-1])
							chain = pm.chain.path
							path = case data[:start]
							when true
								chain.length > 2 ? chain[1..-1] : nil
							else
								chain.length > 2 ? chain[0..-2] : nil
							end
							if path.nil?
								@state = "pick"
								reset
							else
								pm.set_chain(path)
								pm.draw
								@ip1 = data[:start] ? Sketchup::InputPoint.new(path[0]) : Sketchup::InputPoint.new(path[-1])
							end
						end
					end
				when 16
					if @member_path || @face
						change_cursor("get")
						onSetCursor
					end
				end
				view.invalidate
				#onMouseMove(@pos[0],*@pos[1], view)

			end

			def onUserText(text, view)

				return if @state != "click-click"
				begin
					value = text.to_l
				rescue
					# Error parsing the text
					UI.beep
					puts "Cannot convert #{text} to a Length"
					value = nil
					Sketchup::set_status_text "", SB_VCB_VALUE
				end
				return if !value

				if( value.to_f < 0.01 )
					UI.beep
					return
				end
				case @sub_click
				when "append"
					vector = @pts[1].vector_to(@pts[0])
					@pts[0] = @pts[1].offset(vector, value)
					do_append
				when "extend"
					vector = @pts[1].vector_to( @pts[0].project_to_line( @click_click_data[:line]))
					@pts[0] = @pts[1].offset(vector, value)
					do_extend
				when "moving"
					vector = @pts[1].vector_to(@pts[0])
					@pts[0] = @pts[1].offset(vector, value)
					do_moving
				when "adjust"
					vector = @pts[1].vector_to(@pts[0])
					@pts[0] = @pts[1].offset(vector, value)
					do_adjust
				when "draw"
					vector = @pts[1].vector_to(@pts[0])
					@pts[0] = @pts[1].offset(vector, value)
					do_draw_member
				end

			end

			def getMenu(menu, flags, x, y, view)
				case @state

				when "pick"
					if @member_path
					profile = @member.profile
					profile.set_from_profile_member(@member)
					# when a member/branch is hilighted
						if !@closest_point
							#if profile == @temp_profile
								menu.add_item("Add Point To Member's Chain"){
									add_point_to_member_chain
								}
								menu.add_item("Start A New Member"){
									start_new_member(view)
								}
								menu.add_item("Split Member At Point"){
									split_member_at_point
								}
								chain = @member.chain
								path = chain.path

								sub_menu = menu.add_item("Miter Joints Split"){
									miter_joint_split
								}
								status = menu.set_validation_proc(sub_menu)  {
									if chain.length > 2
										MF_ENABLED
									else
										MF_GRAYED
									end
									}

								temp_title = chain.closed_path? ? "Unclosed Member's Chain" : "Close Member's Chain"
								sub_menu = menu.add_item(temp_title){
									toggle_chain_closed(chain)
								}
								status = menu.set_validation_proc(sub_menu)  {
									if chain.length > 2
										MF_ENABLED
									else
										MF_GRAYED
									end
									}

								menu.add_separator

								menu.add_item('Rename Shape'){
									rename_member_profile
								}

								menu.add_item('Stamp Shape'){
									edit_member_profile(profile)
								}

								menu.add_separator

							#else
							#end


							menu.add_item('Mirror Shape'){
								mirror_member_profile
							}

							menu.add_item("Shape Alignment: #{al[@member.placement_point.to_i - 1]}"){
								set_member_profile_alignment
							}
							menu.add_item("Shape Rotation: #{@member.rotation}°"){
								member_profile_rotation
							}
							menu.add_separator
							menu.add_item("Shape Width: #{@member.profile.width.to_l}"){
								member_profile_width
							}
							menu.add_item("Shape Height: #{@member.profile.height.to_l}"){
								member_profile_height
							}
							menu.add_separator
							menu.add_item('Reverse Member'){
								reverse_member
							}
							menu.add_item('Delete Member'){
								delete_member
							}
							menu.add_separator

							menu.add_item("Get Shape \"#{@member.profile.fullname}\""){
								@temp_profile.set_from_profile_member(@member)
								if VBO::ShapeForge.profile_dialog_visible?
									VBO::ShapeForge.profile_dialog.temp_profile = @temp_profile
									VBO::ShapeForge.profile_dialog.temp_profile.preview(VBO::ShapeForge.profile_dialog.dialog)
								end
							} if flags == 2

							menu.add_item("Apply Shape \"#{@temp_profile.fullname}\" To Member"){
								Sketchup.active_model.start_operation("ShapeForge - Apply Shape", true)
								@member.set_from_profile!(@temp_profile)
								Sketchup.active_model.commit_operation
							} if @temp_profile

							menu.add_item("Append Shape \"#{@temp_profile.fullname}\" To Path"){
								append_profile
							} if @temp_profile

							menu.add_separator

							menu.add_item("Save Member's Shape As .skp"){
								save_member_profile
							}
							menu.add_item("Load Member's Shape From .skp"){
								load_member_profile
							}
						else
							#puts @closest_point, @index_adjust
							if [ @member.chain.length - 1, 0].include?(@index_adjust)
								menu.add_item("Reset Cap"){
									reset_cap
								}
							else
								menu.add_item("Split Member At Point"){
									split_member_at_point
								}
								#sub = menu.add_submenu("Split Member At Point")
								#sub.add_item("Normal"){
								#	split_at_point("normal")
								#}
								#sub.add_item("Miter Joint"){
								#	split_at_point("miter joint")
								#}
							end
							if @pos[2]
								groups = @member.instance.parent.entities.find_all{|c|
									VBO::ShapeForge::Identify.profile_member?(c) && c != @member.instance && [VBO::ShapeForge::ForgeElement.new(c).chain[0], VBO::ShapeForge::ForgeElement.new(c).chain[-1]].include?(@member.chain[@index_adjust])
									}
									# puts groups
								menu.add_item("Join these 2 members"){
									Sketchup.active_model.start_operation("VBO ShapeForge - Join Members", true)
									pm = VBO::ShapeForge::ForgeElement.new(groups[0])
									if @member.chain[@index_adjust] == pm.chain[0]
										if @pos[2] == 1
											chain = @member.chain.path + pm.chain.path[1..-1]
											@member.set_attribute("cap_1_trim", pm.get_attribute("cap_1_trim"))
										else
											chain = pm.chain.path[1..-1].reverse + @member.chain.path
											@member.set_attribute("cap_0_trim", pm.get_attribute("cap_1_trim"))
										end
									else
										if @pos[2] == 0
											chain =  pm.chain.path + @member.chain.path[1..-1]
											@member.set_attribute("cap_0_trim", pm.get_attribute("cap_0_trim"))
										else
											chain =  @member.chain.path[1..-1] + pm.chain.path.reverse
											@member.set_attribute("cap_1_trim", pm.get_attribute("cap_0_trim"))
										end
									end
									@member.set_chain chain
									@member.draw
									pm.instance.erase!
									Sketchup.active_model.commit_operation
								} if groups.length == 1
							end
							menu.add_item("Start A New Member"){
								start_new_member(view)
							}
							menu.add_item("Remove Chain's Point"){
								remove_chain_point
							}
							chain = @member.chain
							path = chain.path
							temp_title = chain.closed_path? ? "Unclosed Member's Chain" : "Close Member's Chain"
							sub_menu = menu.add_item(temp_title){
								toggle_chain_closed(chain)
							}
							status = menu.set_validation_proc(sub_menu)  {
								if chain.length > 2
									MF_ENABLED
								else
									MF_GRAYED
								end
								}

						end
					else
						if @temp_profile
							menu.add_item('Stamp Shape'){
								edit_temp_profile(view, x, y)
							}
							menu.add_item('Rename Shape'){
								rename_temp_profile
							}
							menu.add_separator

							menu.add_item('Mirror Shape'){
								mirror_temp_profile
							}

							menu.add_item("Shape Alignment: #{al[@temp_profile.placement_point.to_i - 1]}"){
								set_temp_profile_alignment
							}
							menu.add_item("Shape Rotation: #{@temp_profile.rotation}°"){
								temp_profile_rotation
							}
							menu.add_separator
						end
						menu.add_item("Save Shape \"#{@temp_profile.fullname}\" As .skp"){
							save_temp_profile
						} if @temp_profile

						menu.add_item('Load Shape From .skp'){
							skp = UI.openpanel("Load ProfileBuilder's Shape", "", "SketchUp Files|*.skp||")
							if skp
								@temp_profile = VBO::ShapeForge::Shape.new(skp)
							end
						} #if flags == 2
					end
				when "click-click"
					case @sub_click
					when "extend"
					when "draw"
					when "moving", "append"
						chain = @member.chain
						path = chain.path
						temp_title = chain.closed_path? ? "Unclosed Member's Chain" : "Close Member's Chain"
						sub_menu = menu.add_item(temp_title){
							toggle_chain_closed(chain)
						}
						status = menu.set_validation_proc(sub_menu)  {
							if chain.length > 2
							  MF_ENABLED
							else
							  MF_GRAYED
							end
						  }
					when "adjust"
					end
				end
			end

			private

			def lock_axis(view, axis)
				if view.inference_locked?
					view.lock_inference
				end
				if @ip1.valid?
					p2 = @ip1.position
					p1 = @pts[1]
					vec = p1.vector_to(p2)
					len = vec.dot(axis)
					len = 1.0 if len == 0.0
					offset_vector = Geom::Vector3d.new(axis)
					offset_vector.length = len
					ip = Sketchup::InputPoint.new(@pts[1])
					@ip1 = Sketchup::InputPoint.new(@pts[1].offset(offset_vector))
					view.lock_inference(ip, @ip1)
				end
			end

			def on_cap?(view, point)
				return if @member_path.nil? || @member_path.to_s.include?('Delete') || (@pts.empty? && @state == "click-click") || @closest_point
				begin
					transformation = Sketchup::InstancePath.new(@member_path).transformation
				rescue ArgumentError
					@member_path = nil
					return nil
				end
				vertices = @member.get_cap_vertices.delete_if{|c| c.nil?}
				vertices.index{|cap|
					Geom.point_in_polygon_2D(point, cap.map{|p| view.screen_coords(p.position.transform(transformation))}, true)
				}
			end

			def set_on_mouse_move_data(flags, x, y, view)
				@ip1 = view.inputpoint x,y
				if Sketchup.active_model.active_path
					edge = @ip1.edge
					face = @ip1.face
					path = nil
					path =  @ip1.instance_path.to_a if edge
					path =  @ip1.instance_path.to_a if face

				else

					ph = view.pick_helper
					ph.do_pick(x, y)
					path = ph.path_at(0)
					path[-1] = path[-1].edges[0] if path && path[-1].is_a?(Sketchup::Vertex)
				end


				if path
					pick_transformation = Sketchup::InstancePath.new(path).transformation
					active_transformation = Sketchup.active_model.edit_transform.inverse
					i = path.to_a.index{|c| VBO::ShapeForge::Identify.profile_member?(c)}
					member_path = i.nil? ? nil : path.slice(0, i + 1)
					face = (member_path.nil? || flags == 8) && path[-1].is_a?(Sketchup::Face) ? path[-1] : nil
					edge = (member_path.nil? || flags == 8) && path[-1].is_a?(Sketchup::Edge) ? path[-1] : nil
					if member_path && (@selection.include?(member_path) || @selection.empty?)
						member = VBO::ShapeForge::ForgeElement.new(member_path[-1])
						transformation = pick_transformation
						chain = member.chain.path.map{|c| c.transform(transformation)}
						index_adjust = chain.find_index{|c| view.screen_coords(c).distance([x,y,0]) < 20 * UI.scale_factor}
						closest_point = index_adjust.nil? ? nil : chain[index_adjust]
					else
						member_path = nil
					end
				else
					member_path = @selection.empty? ? nil : @selection[0]
					if member_path
						begin
							pick_transformation = Sketchup::InstancePath.new(member_path).transformation
						rescue ArgumentError
							@selection.delete_at(0)
							member_path = nil
						end
						if member_path
							active_transformation = Sketchup.active_model.edit_transform.inverse
							member = VBO::ShapeForge::ForgeElement.new(member_path[-1])
							transformation = pick_transformation
							chain = member.chain.path.map{|c| c.transform(transformation)}
							index_adjust = chain.find_index{|c| view.screen_coords(c).distance([x,y,0]) < 20 * UI.scale_factor}
							closest_point = index_adjust.nil? ? nil : chain[index_adjust]
						end
					end
					face = nil
					edge = nil#
				end
				oncap= on_cap?(view, [x,y])
				if oncap
					pos = [flags,[x,y], oncap]
				elsif (closest_point && [chain[0], chain[-1]].include?(closest_point))
					pos = [flags, [x,y], [chain[0], chain[-1]].index(closest_point)]
				else
					pos = [flags, [x,y],nil]
				end
				pickray = view.pickray(x,y)
				@cls = member.chain.closest_point_on_chain(pickray, transformation) if member
				[path, member_path, member, pos, pickray, pick_transformation, active_transformation, face, edge, closest_point, index_adjust]
			end

			def set_click_click_data(member = @member, member_path = @member_path)
				if @sub_click != "draw"
					if @active_transformation.nil?
						@sub_click = "draw"
						point = @closest_point ? @closest_point : @ip1.position
						@click_click_data = {
								point: point
							}
						@pts = [@click_click_data[:point], @click_click_data[:point]]
						return
					end
					transformation = current_member_transformation(member_path, member)
					chain = member.chain.path.map{|c| c.transform(transformation)}
					case @sub_click
					when "extend"
						@click_click_data = case @pos[2]
						when 0
							{
								point: chain[0],
								vector: chain[1].vector_to(chain[0]),
								member: member,
								member_path: member_path,
								start: true,
								end: false
							}
						when 1
							{
								point: chain[-1],
								vector: chain[-2].vector_to(chain[-1]),
								member: member,
								member_path: member_path,
								start: false,
								end: true
							}
						end
						@click_click_data[:line] =[@click_click_data[:point], @click_click_data[:vector]]
						@ip1.copy! Sketchup::InputPoint.new @click_click_data[:point]
					when "moving"
						case @pos[2]
						when 0
							@click_click_data = {
								point: chain[1],
								member: member,
								member_path: member_path,
								start: true,
								end: false
							}
							@ip1.copy! Sketchup::InputPoint.new chain[0]
						when 1
							@click_click_data = {
								point: chain[-2],
								member: member,
								member_path: member_path,
								end: true,
								start: false
							}
							@ip1.copy! Sketchup::InputPoint.new chain[-1]
						end
					when "append"
						@click_click_data = case @pos[2]
						when 0
							{
								point: chain[0],
								member: member,
								member_path: member_path,
								start: true,
								end: false
							}
						when 1
							{
								point: chain[-1],
								member: member,
								member_path: member_path,
								end: true,
								start: false
							}
						end
						@ip1.copy! Sketchup::InputPoint.new @click_click_data[:point]
					when "adjust"
						@click_click_data = case @pos[2]
						when 0
							{
								point: chain[@index_adjust],
								member: member,
								member_path: member_path,
								start: true,
								end: false
							}
						when 1
							{
								point: chain[@index_adjust],
								member: member,
								member_path: member_path,
								start: false,
								end: true
							}
						else
							{
								point: chain[@index_adjust],
								member: member,
								member_path: member_path,
							}

						end
						@ip1.copy! Sketchup::InputPoint.new @click_click_data[:point]
					end
					@pts = [@click_click_data[:point], @click_click_data[:point]]
				else
					point = @closest_point ? @closest_point : @ip1.position
					@click_click_data = {
							point: point
						}
					@pts = [@click_click_data[:point], @click_click_data[:point]]
					@ip1.copy! Sketchup::InputPoint.new @click_click_data[:point]
				end

			end
			def draw_picked_face(view, color = @face_color, member = false)
				VBO::ShapeForge::DRAWVIEW.draw_face(@path, color, view)
				if member
					@selection_color.alpha = 200
					view.drawing_color = @selection_color
					transformation =  @pick_transformation
					chain = @face.outer_loop.vertices.map{|c| c.position.transform(transformation )}
					chain << chain[0]
					pm = Extruder.new(chain, @temp_profile)
					pm.draw_view(0, -1, view)
				end

			end

			def draw_picked_edge(view, vertices)
				transformation = Sketchup::InstancePath.new(@path).transformation
				chain = vertices.map{|p| p.position.transform(transformation)}
				VBO::ShapeForge::DRAWVIEW.draw_path3d(view, chain, @edge_color)
				@selection_color.alpha = 200
				view.drawing_color = @selection_color
				pm = Extruder.new(chain, @temp_profile)
				pm.draw_view(0, -1, view)
			end

			def draw_member(view, pm = nil, transformation = nil, show_bounds = true)
				return if @member_path.nil? || (@path.nil? && @selection.empty?)
				if pm.nil?
					VBO::ShapeForge::DRAWVIEW.draw_instance_ref(@member_path, @member_color, view, false) if show_bounds
					transformation = Sketchup::InstancePath.new(@member_path).transformation
					pm = VBO::ShapeForge::ForgeElement.new(@member_path[-1])
				end

				chain = pm.chain.path.map{|c| c.transform(transformation)}
				VBO::ShapeForge::DRAWVIEW.draw_path3d(view, chain, @chain_color)
				view.line_stipple = ''
				#point = pm.chain.closest_point_on_chain(@pickray, transformation)[1]
				#return if point.nil?
				#view.draw_points(point, 15 * UI.scale_factor, 1, @chain_color) if !@closest_point# && point.distance(view.camera.eye) > 1000
				return if @cls[1].nil?
				view.draw_points(@cls[1], 15 * UI.scale_factor, 1, @chain_color) if !@closest_point# && point.distance(view.camera.eye) > 1000

				if !@selection.empty?
					chain.each{|c|
						@cpoints << Sketchup.active_model.active_entities.add_cpoint(c) if @cpoints.include? c
						@cpoints.delete_if{|pt| !chain.path.include?(pt)}
					}
				else
					@cpoints.each{|c| c.erase!}
					@cpoints = []
				end
				view.draw_points(@closest_point, 20 * UI.scale_factor, 2, @chain_color) if @closest_point #&& ![chain[0], chain[-1]].include?(@closest_point)
			end

			def draw_extend(view)
				case @sub_click
				when "extend"
					vector = @pts[1].vector_to @pts[0].project_to_line( @click_click_data[:line])
					if vector.length != 0
						if @trim_objects
							case @trim_objects[:pos][0] #check flags
							when 4
								face = @trim_objects[:face]
								if face
									hover_trans = Sketchup::InstancePath.new(@trim_objects[:path]).transformation
									plane = [face.vertices[0].position, face.normal].map{|c| c.transform(hover_trans)}
									VBO::ShapeForge::DRAWVIEW.draw_path3d(view, [@pts[1], Geom.intersect_line_plane([@pts[1], vector],plane)], @branch_color)

								end
							when 8
								solid = @trim_objects[:solid]
								if solid
									hover_trans = Sketchup::InstancePath.new(@trim_objects[:path]).transformation
									ray = [@pts[1],vector]
									ray_test = Sketchup.active_model.raytest(ray).to_a
									if ray_test[0]
										VBO::ShapeForge::DRAWVIEW.draw_path3d(view, [@pts[1], ray_test[0]], @branch_color)
									else
										VBO::ShapeForge::DRAWVIEW.draw_path3d(view, [@pts[1], @pts[0].project_to_line( @click_click_data[:line])], @branch_color)
									end
								end
							end
						else
							VBO::ShapeForge::DRAWVIEW.draw_path3d(view, [@pts[1], @pts[0].project_to_line( @click_click_data[:line])], @selection_color)
						end
					end
				when "moving", "append", "draw"
					VBO::ShapeForge::DRAWVIEW.draw_path3d(view, [@ip1, @ip2].map{|c| c.position}, view.inference_locked? ? nil : @branch_color)
					if @sub_click != "draw"
						transformation = current_member_transformation(@click_click_data && @click_click_data[:member_path], @click_click_data && @click_click_data[:member])
						index = @index_adjust
						chain = @member.chain.path.map{|c| c.transform(transformation)}
						i = case index
						when 0
							@member.closed_path? ? nil : @sub_click == "moving" ? 1 : 0
						when (chain.length - 1)
							@member.closed_path? ? nil : @sub_click == "moving" ? -2 : -1
						else
						nil
						end
						VBO::ShapeForge::DRAWVIEW.draw_path3d(view, [chain[i], @pts[0]], @member_color) if i
					end
				when "adjust"
					transformation = current_member_transformation(@click_click_data && @click_click_data[:member_path], @click_click_data && @click_click_data[:member])
					chain = @member.chain.path.map{|c| c.transform(transformation)}
					index = @index_adjust
					i,j = case index
					when 0
						@member.closed_path? ? [-2, 1] : [-1, 1]
					when (chain.length - 1)
						@member.closed_path? ? [-2, 1] : [-2, 0]
					when nil
						nil
					else
						[index -1, index + 1]
					end
					VBO::ShapeForge::DRAWVIEW.draw_path3d(view, [@ip1, @ip2].map{|c| c.position}, view.inference_locked? ? nil : @branch_color)
					VBO::ShapeForge::DRAWVIEW.draw_path3d(view, [chain[i], @pts[0], chain[j]], @member_color)
				end
				draw_profile_3d(view, @selection_color)
				view.draw_points(@closest_point, 20 * UI.scale_factor, 2, @chain_color) if @closest_point
			end

			def draw_profile(view, profile = @temp_profile)
				return if profile.nil?  || @pos[1].nil?
				profile_bounds = Geom::BoundingBox.new
				profile_bounds.add(profile.get_transformed_loop( profile.outer_loop))
				scale = 24 * UI.scale_factor / [profile_bounds.width, profile_bounds.height].max
				profile_bounds = Geom::BoundingBox.new.add(profile.outer_loop)
				mouse_trans = Geom::Transformation.translation(@pos[1].map{|pp| pp + 24 * UI.scale_factor})
				trans = Geom::Transformation.scaling(@pos[1].map{|pp| pp + 24 * UI.scale_factor}, scale)
				screen_trans = Geom::Transformation.scaling(@pos[1].map{|pp| pp + 24 * UI.scale_factor}, 1, -1, 1)
				outer_loop = profile.get_transformed_loop( profile.outer_loop).map{|c| c.offset(@pos[1].map{|pp| pp + 24 * UI.scale_factor})}.map{|c| c.transform(trans * screen_trans)}

				b_table = profile.get_transformed_loop((0..3).to_a.map{|c| profile_bounds.corner(c).to_a}).map{|c| c.offset(@pos[1].map{|pp| pp + 24 * UI.scale_factor})}.map{|c| c.transform(trans * screen_trans)}
				grid = VBO::ShapeForge.align_table(b_table)
				mirror_trans = Geom::Transformation.scaling(grid[5], 1, -1, 1)
				point = grid[profile.placement_point.to_i - 1].transform(mirror_trans)
				view.line_width = 2
				if profile.is_2d?
					holes = profile.holes.delete_if{|c| c.length < 3}.map{|hole|
						profile.get_transformed_loop(hole.reverse).map{|c| c.offset(@pos[1].map{|pp| pp + 24 * UI.scale_factor})}.map{|c| c.transform(trans * screen_trans)}
					}
					@profile_color.alpha = 200
					view.drawing_color = @profile_color
					view.draw2d(GL_LINE_LOOP, outer_loop)
					holes.each{|hole| view.draw2d(GL_LINE_LOOP, hole)}
					@profile_color.alpha = 100
					view.drawing_color = @profile_color
				else
					@profile_color.alpha = 200
					view.drawing_color = @profile_color
					view.draw2d(GL_LINE_STRIP, outer_loop)
				end
				VBO::ShapeForge::DRAWVIEW.draw_point_2d(view, point, 3 * UI.scale_factor, @chain_color)
			end

			def current_member_transformation(member_path = @member_path, member = @member)
				candidate_paths = [
					member_path,
					@click_click_data && @click_click_data[:member_path],
					@member_path,
					member
				].compact

				candidate_paths.each do |path|
					path = normalize_member_path(path, member)
					next if path.nil?
					begin
						return Sketchup::InstancePath.new(path).transformation
					rescue ArgumentError, TypeError
					end
				end

				return member.transformation if member && member.respond_to?(:transformation)
				if @click_click_data && @click_click_data[:member] && @click_click_data[:member].respond_to?(:transformation)
					return @click_click_data[:member].transformation
				end

				@pick_transformation || Geom::Transformation.new
			end

			def normalize_member_path(path, member = nil)
				if path.is_a?(Array)
					return path if !path.empty? && path[-1].respond_to?(:definition)
				elsif path.respond_to?(:definition)
					return Sketchup.active_model.active_path.to_a + [path]
				elsif path.respond_to?(:instance)
					instance = path.instance
					return Sketchup.active_model.active_path.to_a + [instance] if instance && instance.respond_to?(:definition)
				end

				if member && member.respond_to?(:instance)
					instance = member.instance
					return Sketchup.active_model.active_path.to_a + [instance] if instance && instance.respond_to?(:definition)
				end

				nil
			end

			def preview_local_chain_for_active_sub_click
				data = @click_click_data || {}
				member = data[:member] || @member
				return nil unless member

				member_path = normalize_member_path(data[:member_path], member)
				transformation = current_member_transformation(member_path, member)
				chain = member.chain.path.map { |point| point.clone }

				case @sub_click
				when "moving"
					return nil if @pts[0] == @pts[1]
					target_point = @pts[0].transform(transformation.inverse)
					if data[:start]
						chain[0] = target_point
					elsif data[:end]
						chain[-1] = target_point
					end
				when "append"
					return nil if @pts[0] == @pts[1]
					target_point = @pts[0].transform(transformation.inverse)
					if data[:start]
						chain.unshift(target_point)
					elsif data[:end]
						chain << target_point
					end
				when "adjust"
					return nil if @pts[0] == @pts[1]
					index = @index_adjust
					return nil if index.nil?
					target_point = @pts[0].transform(transformation.inverse)

					i, j = case index
					when 0
						member.closed_path? ? [-2, 1] : [-1, 1]
					when (chain.length - 1)
						member.closed_path? ? [-2, 1] : [-2, 0]
					else
						[index - 1, index + 1]
					end

					if [i, j] == [-2, 1]
						chain[0] = target_point
						chain[-1] = chain[0]
					else
						chain[index] = target_point
					end

					chain.delete_at(j) if j && chain[index] == chain[j]
					chain.delete_at(i) if i && chain[index] == chain[i]
				when "extend"
					return nil if @pts[0] == @pts[1]
					projected_point = @pts[0].project_to_line(data[:line]).transform(transformation.inverse)
					return nil if projected_point == member.chain.path[data[:start] ? 0 : -1]

					if data[:start]
						chain[0] = projected_point
					elsif data[:end]
						chain[-1] = projected_point
					end
				else
					return nil
				end

				{
					chain: chain,
					member: member,
					transformation: transformation,
					member_path: member_path
				}
			end

			def actual_cap_loops_world(member, transformation, start_cap)
				return nil unless member && member.respond_to?(:entities)

				chain_world = member.chain.path.map { |pt| pt.transform(transformation) }
				return nil if chain_world.length < 2

				cap_idx = start_cap ? 0 : chain_world.length - 1
				endpoint = chain_world[cap_idx]
				extend_vector = start_cap ? chain_world[1].vector_to(chain_world[0]) : chain_world[-2].vector_to(chain_world[-1])
				return nil unless extend_vector.valid?

				best_face = member.entities.grep(Sketchup::Face).filter_map { |face|
					normal_world = face.normal.transform(transformation)
					next nil unless normal_world.valid? && normal_world.parallel?(extend_vector)

					plane = [face.vertices[0].position.transform(transformation), normal_world]
					projected_point = endpoint.project_to_plane(plane)
					plane_distance = endpoint.distance(projected_point)
					next nil if plane_distance > 1.mm

					bounds = Geom::BoundingBox.new
					face.outer_loop.vertices.each { |vertex| bounds.add(vertex.position.transform(transformation)) }
					[plane_distance + bounds.center.distance(endpoint), face]
				}.min_by(&:first)

				return nil unless best_face

				best_face[1].loops.sort_by { |loop| loop.outer? ? 0 : 1 }.map { |loop|
					loop.vertices.map { |vertex| vertex.position.transform(transformation) }
				}
			end

			def draw_translated_cap_preview(view, target_point)
				data = @click_click_data
				member = data[:member] || @member
				return false unless member && data

				cap_idx = data[:start] ? 0 : member.chain.path.length - 1
				transformation = current_member_transformation(data[:member_path], member)
				source_point = member.chain.path[cap_idx].transform(transformation)
				offset_vec = source_point.vector_to(target_point)
				loops_world = actual_cap_loops_world(member, transformation, data[:start])
				if loops_world.nil? || loops_world.empty?
					cap_junction = member.profile_loops_at(cap_idx)
					return false if cap_junction.nil? || cap_junction.empty?
					loops_world = cap_junction.map { |loop| loop.map { |pt| pt.transform(transformation) } }
				end
				moved_loops = loops_world.map { |loop| loop.map { |pt| pt.offset(offset_vec) } }

				preview_color = Sketchup::Color.new("brown")
				preview_color.alpha = 200
				view.line_width = 1
				view.drawing_color = preview_color

				loops_world.zip(moved_loops).each do |original_loop, moved_loop|
					if member.profile.is_2d?
						view.draw(GL_LINE_LOOP, original_loop)
						view.draw(GL_LINE_LOOP, moved_loop)
					else
						view.draw(GL_LINE_STRIP, original_loop)
						view.draw(GL_LINE_STRIP, moved_loop)
					end

					original_loop.zip(moved_loop).each do |segment|
						view.draw(GL_LINE_STRIP, segment)
					end
				end

				true
			end

			def draw_preview_loop_section(view, section, profile)
				section.each do |loop|
					profile.is_2d? ? view.draw(GL_LINE_LOOP, loop) : view.draw(GL_LINE_STRIP, loop)
				end
			end

			def profile_loops_world(member, transformation, junction_index)
				return nil unless member
				loops = member.profile_loops_at(junction_index)
				return nil if loops.nil? || loops.empty?

				loops.map { |loop| loop.map { |point| point.transform(transformation) } }
			end

			def align_loop_to_reference(reference_loop, target_loop)
				return target_loop if reference_loop.nil? || target_loop.nil? || reference_loop.length != target_loop.length

				candidates = [target_loop, target_loop.reverse]
				best_loop = target_loop
				best_score = nil

				candidates.each do |candidate|
					candidate.length.times do |offset|
						rotated = candidate.rotate(offset)
						score = reference_loop.each_with_index.sum { |point, index| point.distance(rotated[index]) }
						if best_score.nil? || score < best_score
							best_score = score
							best_loop = rotated
						end
					end
				end

				best_loop
			end

			def align_section_to_reference(reference_section, target_section)
				return target_section if reference_section.nil? || target_section.nil?

				reference_section.zip(target_section).map do |reference_loop, target_loop|
					align_loop_to_reference(reference_loop, target_loop)
				end
			end

			def draw_preview_segment_sections(view, start_section, end_section, profile)
				return false if start_section.nil? || end_section.nil?

				draw_preview_loop_section(view, start_section, profile)
				start_section.zip(end_section).each_with_index do |loops, index|
					loops[0].zip(loops[1]).each { |segment| view.draw(GL_LINE_STRIP, segment) } if index == 0
				end
				draw_preview_loop_section(view, end_section, profile)
				true
			end

			def draw_straight_member_preview(view, preview_data, target_point, moving_start)
				return false unless preview_data && preview_data[:chain].length == 2

				member = preview_data[:member]
				transformation = preview_data[:transformation]
				profile = member.profile
				profile.set_from_profile_member(member)

				original_start_section = profile_loops_world(member, transformation, 0) || actual_cap_loops_world(member, transformation, true)
				original_end_section = profile_loops_world(member, transformation, member.chain.path.length - 1) || actual_cap_loops_world(member, transformation, false)
				return false if original_start_section.nil? || original_end_section.nil?
				aligned_end_section = align_section_to_reference(original_start_section, original_end_section)

				if moving_start
					source_point = member.chain.path[0].transform(transformation)
					offset_vec = source_point.vector_to(target_point)
					start_section = original_start_section.map { |loop| loop.map { |point| point.offset(offset_vec) } }
					end_section = aligned_end_section
				else
					source_point = member.chain.path[-1].transform(transformation)
					offset_vec = source_point.vector_to(target_point)
					start_section = original_start_section
					end_section = aligned_end_section.map { |loop| loop.map { |point| point.offset(offset_vec) } }
				end

				draw_preview_segment_sections(view, start_section, end_section, profile)
			end

			def draw_split_style_preview(view, preview_data, split_type)
				return false unless preview_data && preview_data[:chain].length > 1
				return false unless ["normal", "miter_joint", "butt_joint"].include?(split_type)

				member = preview_data[:member]
				profile = member.profile
				profile.set_from_profile_member(member)
				transformation = preview_data[:transformation]
				chain_world = preview_data[:chain].map { |point| point.transform(transformation) }
				extruder = Extruder.new(preview_data[:chain], profile)
				junctions = preview_data[:chain].each_index.map { |index|
					extruder.profile_loops_at(index).map { |loop|
						loop.map { |point| point.transform(transformation) }
					}
				}
				return false if junctions.empty?

				last = junctions[0]
				junctions.each_with_index do |this, index|
					next if index == 0

					last_copy = last.map { |loop| loop.map(&:clone) }
					this_copy = this.map { |loop| loop.map(&:clone) }
					sub_start = chain_world[index - 1]
					sub_end = chain_world[index]
					sub_vector = sub_start.vector_to(sub_end)

					case split_type
					when "normal"
						start_plane = [sub_start, sub_vector]
						last_copy = last_copy.map { |loop| loop.map { |point| point.project_to_plane(start_plane) } }
						end_plane = [sub_end, sub_vector.reverse]
						this_copy = this_copy.map { |loop| loop.map { |point| point.project_to_plane(end_plane) } }
					when "miter_joint", "butt_joint"
						if index > 1
							v1 = chain_world[index - 2].vector_to(chain_world[index - 1])
							v2 = v1 * sub_vector
							last_plane_normal = v1 * v2
							last_plane_normal = sub_vector if last_plane_normal.length == 0
						else
							last_plane_normal = sub_vector
						end

						if index < chain_world.length - 1
							v1 = chain_world[index].vector_to(chain_world[index + 1])
							v2 = v1 * sub_vector
							next_plane_normal = v1 * v2
							next_plane_normal = sub_vector if next_plane_normal.length == 0
						else
							next_plane_normal = sub_vector.reverse
						end

						nearest_last = last_copy.flatten.min_by { |point| point.distance(sub_end) }
						start_plane = [nearest_last, last_plane_normal]
						last_copy = last_copy.map { |loop|
							loop.map { |point| Geom.intersect_line_plane([point, sub_vector], start_plane) }
						}

						farthest_this = this_copy.flatten.max_by { |point| point.distance(sub_start) }
						end_plane = [farthest_this, next_plane_normal]
						this_copy = this_copy.map { |loop|
							loop.map { |point| Geom.intersect_line_plane([point, sub_vector], end_plane) }
						}
					end

					draw_preview_segment_sections(view, last_copy, this_copy, profile)
					last = this
				end

				true
			end

			def draw_world_chain_preview(view, preview_data)
				return false unless preview_data && preview_data[:chain].length > 1

				profile = preview_data[:member].profile
				profile.set_from_profile_member(preview_data[:member])
				preview_world_chain = preview_data[:chain].map { |point| point.transform(preview_data[:transformation]) }
				preview_transformation = VBO::ShapeForge::ForgeElement.default_transformation(preview_world_chain)
				pm = Extruder.new(preview_world_chain, profile, preview_transformation)
				pm.draw_view(0, -1, view, preview_transformation)
				true
			end

			def draw_profile_3d(view, color = @profile_color)
				if @state == "click-click"
					data = @click_click_data
					view.drawing_color = color
					view.line_stipple = ""
					case @sub_click
					when "moving", "append", "adjust", "extend"
						member = data[:member] || @member
						junction_style = member&.profile&.junction_style
						preview_data = preview_local_chain_for_active_sub_click
						if @sub_click == "extend"
							target_point = @pts[0].project_to_line(data[:line])
							if preview_data && preview_data[:chain].length == 2 &&
								draw_straight_member_preview(view, preview_data, target_point, data[:start])
							else
								unless target_point == @pts[1]
									draw_translated_cap_preview(view, target_point)
								end
							end
						elsif @sub_click == "moving" && preview_data && preview_data[:chain].length == 2 &&
							draw_straight_member_preview(view, preview_data, @pts[0], data[:start])
						else
							if @sub_click == "append" && draw_split_style_preview(view, preview_data, junction_style)
							elsif preview_data && preview_data[:chain].length > 1
								profile = preview_data[:member].profile
								profile.set_from_profile_member(preview_data[:member])
								pm = Extruder.new(preview_data[:chain], profile)
								pm.draw_view(0, -1, view, preview_data[:transformation])
							elsif @sub_click != "adjust"
								target_point = @pts[0]
								unless target_point == @pts[1]
									draw_translated_cap_preview(view, target_point)
								end
							end
						end
					when "draw"
						if @pts[0] != @pts[1]
							chain = Chain.new(@pts.rotate)
							profile = @temp_profile
							trans = VBO::ShapeForge::ForgeElement.default_transformation(chain.path)
							pm = Extruder.new(chain.path, profile, trans)
							pm.draw_view(0, -1, view, trans)
						end
					end
				else
					transformation = Sketchup::InstancePath.new(@member_path).transformation
					#cls = @member.chain.closest_point_on_chain(@pickray, transformation)

					return if @cls[1].nil?
					point = @cls[1].transform(@pick_transformation.inverse)
					index = @cls[0]

					profile = @member.profile
					profile.set_from_profile_member(@member)
					profiles = [profile]
					profiles << @temp_profile if @temp_profile != profile

					m_chain = @member.chain

					if @closest_point
						vector = case @index_adjust
						when 0
							[0,0,0]
						when m_chain.length - 1
							if !@member.closed_path?
								if m_chain.length > 2
									m_chain.path[-2].transform(@pick_transformation).vector_to(m_chain.path[-1].transform(@pick_transformation))
								else
									m_chain[0].transform(@pick_transformation).vector_to(m_chain[1].transform(@pick_transformation))
								end
							else
								nil
							end
						else
							nil
						end
						#point = m_chain[@index_adjust].transform(@pick_transformation)
					elsif @pos[2]
						vector = case @pos[2]
						when 0
							[0,0,0]
						when 1
							if !@member.closed_path?
								if m_chain.length > 2
									m_chain.path[-2].transform(@pick_transformation).vector_to(m_chain.path[-1].transform(@pick_transformation))
								else
									m_chain[0].transform(@pick_transformation).vector_to(m_chain[1].transform(@pick_transformation))
								end
							else
								nil
							end
						end
					else
						vector = (m_chain[index].vector_to(point)).transform(@pick_transformation)
					end
					if vector
						colors = profiles.length > 1 ? [Sketchup::Color.new("red"), Sketchup::Color.new("Darkgreen")] : [Sketchup::Color.new("magenta"), Sketchup::Color.new("Darkgreen")]
						alpha = [200, 200]
						weight = [2, 3]
						profiles.each_with_index{|profile, i|
							l1 = profile.get_transformed_loop profile.outer_loop
							trans_at_end = m_chain.transformation_at(index)
							temp_loops = l1.map{|c| c.transform(@pick_transformation * trans_at_end ).offset(vector)}
							outer_loop = temp_loops
							view.line_width = 3
							if profile.is_2d?
								colors[i].alpha = alpha[i]
								view.drawing_color = colors[i]
								view.line_width = weight[i]
								view.draw(GL_LINE_LOOP, outer_loop)
							else
								colors[i].alpha = alpha[i]
								view.drawing_color = colors[i]
								view.line_width = weight[i]
								view.draw(GL_LINE_STRIP, outer_loop)
							end
						}
					end
=begin
					cls = @member.chain.closest_point_on_chain(@pickray, transformation)
					return if cls[1].nil?
					point = cls[1].transform(transformation.inverse)
					index = cls[0]

					profile = @member.profile
					profile.set_from_profile_member(@member)
					profiles = [profile]
					profiles << @temp_profile if @temp_profile != profile

					m_chain = @member.chain.path.map{|c| c.transform(transformation)}
					#@closest_point = m_chain[-@pos[2]] if @pos[2]

					colors = profiles.length > 1 ? [Sketchup::Color.new("red"), Sketchup::Color.new("Darkgreen")] : [Sketchup::Color.new("Darkcyan"), Sketchup::Color.new("Darkgreen")]
					transformation = Sketchup::InstancePath.new(@member_path).transformation
					alpha = [200, 200]
					weight = [2, 3]
					profiles.each_with_index{|profile, i|
						pm = Extruder.new(m_chain, profile)
						outer_loop = @closest_point ? pm.profile_loops_at(m_chain.index(@closest_point))[0] : pm.profile_loops_at_point(@pickray, transformation)

						view.line_width = 3
						if profile.is_2d?
							colors[i].alpha = alpha[i]
							view.drawing_color = colors[i]
							view.line_width = weight[i]
							view.draw2d(GL_LINE_LOOP, outer_loop.map{|c| view.screen_coords(c)})
						else
							colors[i].alpha = alpha[i]
							view.drawing_color = colors[i]
							view.line_width = weight[i]
							view.draw2d(GL_LINE_STRIP, outer_loop)
						end
					}
=end
				end
			end

			def draw_selection(view)
				@selection.to_a.each{|path|
					next unless path.is_a?(Array) && path[-1].respond_to?(:definition)
					begin
						path[-1].definition.entities.find_all{|c| c.is_a? Sketchup::Face}.each{|c|
							VBO::ShapeForge::DRAWVIEW.draw_face3d(path + [c], @selection_color, view)
						}
					rescue => e
						# skip invalid selection entry
					end
					#VBO::ShapeForge::DRAWVIEW.draw_instance_ref(path, @selection_color, view)
				}
			end

			def do_extend
				data = @click_click_data
				transformation = Sketchup::InstancePath.new(@member_path).transformation
				chain = data[:member].chain.path

				if @trim_objects
					case @trim_objects[:pos][0] #check flags
					when 4
						trim_member_to_plane(data, transformation, chain)
					when 8
						trim_member_to_solid(data, transformation, chain)
					end
				else
					extend_member(data, transformation, chain)
				end
			end

			def do_append
				Sketchup.active_model.start_operation("VBO ShapeForge - Append To Member", true)
				data = @click_click_data

				transformation = Sketchup::InstancePath.new(data[:member_path]).transformation
				chain = data[:member].chain.path

				if data[:start]
					chain = [@pts[0].transform(transformation.inverse)] + chain
					cap = 0
				else
					chain = chain + [@pts[0].transform(transformation.inverse)]
					cap = 1
				end
				data[:member].set_chain(chain)
				data[:member].delete_attribute("cap_#{cap}_trim")
				data[:member].draw
				#Sketchup.active_model.commit_operation
				#Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member Cap", true)
				trim_after_draw(data[:member])
				@ip1.clear
				@cpoints.each{|c| c.erase!}
				@cpoints = []
				@state = "click-click"
				@sub_click = "append"
				@member_path[-1] = data[:member].instance if @member_path
				set_click_click_data(data[:member], @member_path)
				Sketchup.active_model.commit_operation
				VBO::ShapeForge.manager_need_reload
			end

			def do_moving
				Sketchup.active_model.start_operation("VBO ShapeForge - Move Member Cap", true)
				data = @click_click_data
				begin
					transformation = Sketchup::InstancePath.new(@member_path).transformation
				rescue ArgumentError
					Sketchup.active_model.abort_operation
					@member_path = nil
					reset
					return
				end
				chain = data[:member].chain.path

				if data[:start]
					chain[0] = @pts[0].transform(transformation.inverse)
					cap = 0
				else
					chain[-1] = @pts[0].transform(transformation.inverse)
					cap = 1
				end
				data[:member].set_chain(chain)
				data[:member].delete_attribute("cap_#{cap}_trim")

				draw_mode = chain.length == 2 ? "continuous" : data[:member].profile.junction_style
				data[:member].draw(draw_mode)
				#Sketchup.active_model.commit_operation
				#Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member Cap", true)
				trim_after_draw(data[:member])
				#data[:member].transform!(transformation)

				reset
				@member_path[-1] = data[:member].instance
				VBO::ShapeForge.manager_need_reload
				begin
					data[:member].re_coordinate(Sketchup::InstancePath.new(@member_path).transformation) if data[:start] || chain.length == 2
				rescue ArgumentError
					# instance path became invalid after draw — skip re_coordinate
				end
				Sketchup.active_model.commit_operation
			end

			def do_adjust
				Sketchup.active_model.start_operation("VBO ShapeForge - Move Member Junction", true)
				data = @click_click_data
				transformation = Sketchup::InstancePath.new(@member_path).transformation
				chain = data[:member].chain.path
				index = @index_adjust
				i,j = case index
				when 0
					@member.closed_path? ? [-2, 1] : [-1, 1]
				when (chain.length - 1)
					@member.closed_path? ? [-2, 1] : [-2, 0]
				when nil
					nil
				else
					[index - 1, index + 1]
				end
				if [i,j] == [-2,1]
					chain[0] = @pts[0].transform(transformation.inverse)
					chain[-1] = chain[0]
				else
					chain[@index_adjust] =  @pts[0].transform(transformation.inverse)
				end
				chain.delete_at(j) if chain[@index_adjust] == chain[j]
				chain.delete_at(i) if chain[@index_adjust] == chain[i]

				data[:member].set_chain(chain)
				data[:member].draw
				#Sketchup.active_model.commit_operation
				#Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member Cap", true)
				trim_after_draw(data[:member])
				Sketchup.active_model.commit_operation
				reset
				@member_path[-1] = data[:member].instance
				VBO::ShapeForge.manager_need_reload
			end

			def do_draw_member
				begin
					if @temp_profile.nil?
						@temp_profile = VBO::ShapeForge.load_last_profile
						return if @temp_profile.nil?
					end
					chain = [@pts[1], @pts[0]]
					return if chain[0] == chain[1]
					Sketchup.active_model.start_operation("VBO ShapeForge - Draw Member", true)
					data = @click_click_data
					pm = VBO::ShapeForge::ForgeElement.add(Sketchup.active_model.active_entities, chain)
					if pm.nil?
						Sketchup.active_model.abort_operation
						return
					end
					pm.set_from_profile!(@temp_profile)

					reset
					@member = pm
					@member_path = Sketchup.active_model.active_path.to_a + [@member.instance]
					@path = @member_path + [@member.definition.entities[0]]
					@pick_transformation = Sketchup::InstancePath.new(@member_path).transformation
					@active_transformation = Sketchup.active_model.edit_transform.inverse
					@pos = [nil, nil, 1]
					@state = "click-click"
					@sub_click = "append"
					set_click_click_data
					Sketchup.active_model.commit_operation
					VBO::ShapeForge.manager_need_reload
				rescue => e
					puts "[ShapeForge] ERROR in do_draw_member: #{e.message}"
					puts e.backtrace.first(3).join("\n")
					Sketchup.active_model.abort_operation rescue nil
				end
			end
		end

		class TrimToPlane
			attr_accessor :selected, :face, :state
			def initialize
				@color = Sketchup::Color.new('magenta')
				@state = :select_plane
			end

			def activate
			end

			def reset
				Sketchup.active_model.selection.clear
				@state = :select_plane
			end

			def deactivate(view)
				VBO::ShapeForge.profile_dialog.uncheck('member_toolbar|trim_plane')
			end

			def selected
				Sketchup.active_model.selection.to_a.find_all{|c| Identify.profile_member?(c)}
			end

			def onCancel(reason, view)
				case reason
				when 0
					case @state
					when :select_caps
						@state = :select_plane

					when :select_plane
						reset
					when :select_members
						@state = :select_plane
					end
				end
			end

			def do_trim
				Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member To Plane", true)
				@caps.each{|cap|
					cap_index = cap[3]
					plane = @plane
					cap[4].trim_to_plane(plane, cap_index, cap[4].transformation)
				}
				Sketchup.active_model.commit_operation
			end

			def onLButtonUp(flags, x, y, view)
				sel = Sketchup.active_model.selection
				case @state
				when :select_plane
					if self.selected.empty?
						@state = :select_members
					else
						do_trim
						#reset
					end
				when :select_members
					if @best_picked
						if sel.include?(@best_picked)
							sel.remove(@best_picked)
							@caps.delete(@best_picked)
						else
							sel.add(@best_picked)
							@caps[@best_picked] = caps_lines(@fix_solid, [@best_picked])
						end
						onMouseMove(flags,x,y,view)
					end
					if @path == @fix_face
						do_trim
						reset
					end
				when :select_caps
					if @path == @fix_face
						do_trim
						reset
					elsif @hovered_cap
						exist = @caps.find{|c| c[0..3] == @hovered_cap[0..3] && c[4].instance == @hovered_cap[4].instance}

						if exist
							same_mem = @caps.find{|c| c[4].instance == exist[4].instance}
							@caps.delete(exist)
							@hovered_cap = nil
							if same_mem
							else
								sel.remove(exist[4].instance)
							end
						else
							same_mem = @caps.find{|c| c[4].instance == @hovered_cap[4].instance}
							if same_mem
								if same_mem[4].chain.length == 2
									@caps.delete(same_mem)
								else
									@hovered_cap[4] = same_mem[4]
								end
							else
								sel.add(@hovered_cap[4].instance)
							end
							@caps << @hovered_cap
							@hovered_cap = nil
						end
						onMouseMove(flags,x,y,view)
					elsif @best_picked
						if sel.include?(@best_picked)
							sel.remove(@best_picked)
						else
							sel.add(@best_picked)
						end
						@caps = caps_lines(@plane, true)
					end
				end
			end

			def caps_lines(plane, full = false)
				if plane
					self.selected.map{|s|
						mem = ForgeElement.new(s)
						s = mem.caps.each_with_index.map{|c, i|
							point = c[:point].transform(mem.transformation)
							vector = c[:vector].transform(mem.transformation)
							inter =  Geom.intersect_line_plane([point, vector],plane)
							distance = inter.nil? ? 0 : point.distance(inter)
							[point, inter, distance, i, mem]
						}.reject{|c| c[1].nil?}
						if mem.chain.length == 2 || !full
							s = [s.min_by{|c| c[2]}]
						end
						s
					}.flatten(1).reject{|c| c.nil?}
				else
					[]
				end
			end

			def onKeyUp(key, repeat, flags, view)
				case key
				when 16
					# puts 'shift'
					if @state == :select_caps
						@state = @last_state
						@last_state = nil
					else
						@last_state = @state
						@state = :select_caps
						@caps = caps_lines(@plane, true)
					end
				when 13
					do_trim
					reset
				end
				onMouseMove(@pos[0],*@pos[1], view)
			end

			def onMouseMove(flags,x,y,view)
				ph = view.pick_helper
				ph.do_pick(x, y)
				@path = ph.path_at(0)
				@best_picked = ph.best_picked
				@best_picked = nil unless Identify.profile_member?(@best_picked)
				#puts "#{@path}"
				if @path
					@pos = [flags,[x,y]]
				else
					ip1 = view.inputpoint x,y
					edge = ip1.edge
					face = ip1.face
					@path = nil
					@path =  ip1.instance_path.to_a if edge
					@path =  ip1.instance_path.to_a if face
					@path[-1] = @path[-1].edges[0] if @path && @path[-1].is_a?(Sketchup::Vertex)
				end

				@pos = [flags,[x,y]]
				@face = nil

				if @path
					@face = @path[-1] if @path[-1].is_a?(Sketchup::Face)
					@trans = Sketchup::InstancePath.new(@path).transformation
					if @face && @state == :select_plane
						@plane = [@face.vertices[0].position, @face.normal].map{|c| c.transform(@trans)}
						@fix_face = @path
					end
				end
				if @state == :select_caps
					@hovered_cap = self.selected.map{|s|
						mem = ForgeElement.new(s)
						mem.caps.each_with_index.map{|c, i|
							point = c[:point].transform(mem.transformation)
							vector = c[:vector].transform(mem.transformation)
							inter =  Geom.intersect_line_plane([point, vector], @plane)
							distance = inter.nil? ? 0 : point.distance(inter)
							[point, inter, distance, i, mem]
						}.reject{|c| c[1].nil?}
					}.flatten(1).find{|c| view.screen_coords(c[0]).distance([x,y,0]) <= 15 * UI.scale_factor}
				else
					@caps = caps_lines(@plane)
				end
				view.invalidate
			end

			def draw(view)
				sel = selected
				case @state
				when :select_plane
					unless sel.empty?
						Sketchup.set_status_text "Click on face to trim selected members to plane. Shift: Select Caps"
					else
						Sketchup.set_status_text "Click on face to set a plane"
					end
					DRAWVIEW.draw_face(@path, @color, view, false) if @path

					#DRAWVIEW.draw_boundingbox_ref(view, @path[-1].bounds, @color, Sketchup::InstancePath.new(@path).transformation,  true)

					@caps.to_a.each{|c|
						DRAWVIEW.draw_arrow2d(view, c[0], c[1], Sketchup::Color.new('red'))
					}
				when :select_members
					Sketchup.set_status_text "Click on member to toggle select. Shift: Select Caps. Enter / Click on fixed face to trim selected members to plane"
					DRAWVIEW.draw_face(@fix_face, @color, view, false)

					@caps.each{|c|
						DRAWVIEW.draw_arrow2d(view, c[0], c[1], Sketchup::Color.new('red'))
					}
					if @best_picked
						mem = VBO::ShapeForge::ForgeElement.new(@best_picked)
						color = Sketchup::Color.new('magenta')
						view.drawing_color = color
						# mem.draw_view(0,-1,view)
						VBO::ShapeForge::DRAWVIEW.draw_path3d(
							view,
							mem.chain.path.map{|c|
								c.transform(mem.transformation)
							},
							color
						)
					end
				when :select_caps
					Sketchup.set_status_text "Click on member to select. Click on member's cap to toggle select cap. Enter / Click on fixed face to trim selected members to plane"
					DRAWVIEW.draw_face(@fix_face, @color, view, false)
					@caps.each{|c|
						DRAWVIEW.draw_arrow2d(view, c[0], c[1], Sketchup::Color.new('orange'))
					}
					if @best_picked  && !@hovered_cap

						mem = VBO::ShapeForge::ForgeElement.new(@best_picked)
						color = Sketchup::Color.new('magenta')
						view.drawing_color = color
						# mem.draw_view(0,-1,view)
						VBO::ShapeForge::DRAWVIEW.draw_path3d(
							view,
							mem.chain.path.map{|c|
								c.transform(mem.transformation)
							},
							color
						)
					end
					#puts @caps.length
					if @caps && !@caps.empty?
						view.draw_points(@caps.map{|c| c[0]},5 * UI.scale_factor, 1, Sketchup::Color.new('red'))
						view.draw_points([@hovered_cap[0]] ,15 * UI.scale_factor, 2, Sketchup::Color.new('red')) if @hovered_cap
					end
				end
			end
		end

		class TrimToSolid
			attr_accessor :selected, :solid, :state
			include Geometry
			def initialize
				@color = Sketchup::Color.new('magenta')

				@state = :select_solid
			end

			def activate
			end

			def reset(view)
				Sketchup.active_model.selection.clear
				@caps = nil
				@state = :select_solid
				view.invalidate
			end

			def selected
				Sketchup.active_model.selection.to_a.find_all{|c| Identify.profile_member?(c)}
			end

			def onCancel(reason, view)
				case reason
				when 0
					case @state
					when :select_caps
						@state = :select_solid

					when :select_solid
						reset(view)
					when :select_members
						@state = :select_solid
					end
				end
			end

			def deactivate(view)
				VBO::ShapeForge.profile_dialog.uncheck('member_toolbar|trim_solid')
			end

			def nearest_cap
			end

			def do_trim(solid)
				# puts "do solid trim"
				Sketchup.active_model.start_operation("VBO ShapeForge - Trim Member To solid", true)
				success = true
				if @caps
					@caps.each{|k,v|

						v.group_by{|c| c[4]}.each{|pm, cap|
							if cap.length == 2 &&
								cap[0][0].vector_to(cap[0][1]).parallel?(cap[-1][0].vector_to(cap[-1][1])) &&
								cap[0][4].chain.length == 2

								index = cap.min_by{|c| c[2]}
								lcap = [index]
							else
								lcap = cap.clone
							end

							cap_indecies = lcap.map{|c| c[3]}
							# puts "cap_indecies: #{cap_indecies}"
							b = pm.trim_to_solid(solid, cap_indecies )
							# puts "b: #{b}"
							success = false unless b
						}
					}
					unless success
						UI.messagebox("Some solid issues may occur and have to fix manually. Please check the model.")
						# Sketchup.active_model.abort_operation
					end
					Sketchup.active_model.commit_operation
				end
			end

			def onLButtonUp(flags, x, y, view)
				sel = Sketchup.active_model.selection
				case @state
				when :select_solid
					if @solid
						if self.selected.empty?
							@state = :select_members
							@fix_solid = @solid
							onMouseMove(flags,x,y,view)
						else
							@caps = caps_lines(@solid)
							do_trim(@solid)
							reset(view)
						end
					end
				when :select_members
					if @best_picked
						if sel.include?(@best_picked)
							sel.remove(@best_picked)
							@caps.delete(@best_picked)
						else
							ex = caps_lines(@fix_solid,[@best_picked])
							if ex && !ex[@best_picked].empty?
								sel.add(@best_picked)
								@caps[@best_picked] = ex[@best_picked]
							end
						end
						onMouseMove(flags,x,y,view)
					end
					if @path.include?(@fix_solid[-1])
						do_trim @fix_solid
						reset(view)
					end
				when :select_caps
					if @path.include?(@fix_solid[-1])
						do_trim @fix_solid
						reset(view)
					elsif @hovered_cap
						cps = @caps.values.flatten(1)
						exist = cps.find{|c| c[0..3] == @hovered_cap[0..3] && c[4].instance == @hovered_cap[4].instance}
						if exist
							# puts "exist: #{exist}}"
							same_mem = cps.find{|c| c[4].instance == exist[4].instance}
							@caps[same_mem[4].instance].delete(exist)
							@hovered_cap = nil
							if same_mem
							else
								sel.remove(exist[4].instance)
							end
						else
							same_mem = cps.find{|c| c[4].instance == @hovered_cap[4].instance}
							if same_mem
								@hovered_cap[4] = same_mem[4]
							else
								sel.add(@hovered_cap[4].instance)
							end
							@caps[same_mem[4].instance] << @hovered_cap
							@hovered_cap = nil
						end
						onMouseMove(flags,x,y,view)
					elsif @best_picked
						if sel.include?(@best_picked)
							sel.remove(@best_picked)
							@caps.delete(@best_picked)
						else
							sel.add(@best_picked)
						end
						@caps = caps_lines(@fix_solid)
					end
				end
			end

			def caps_lines(solid, sel = Sketchup.active_model.selection.to_a)
				#t = Time.now
				return unless solid
				members = sel.find_all{|c|
						VBO::ShapeForge::Identify.profile_member?(c)
				}

				trans = Sketchup::InstancePath.new(solid).transformation
				faces = solid[-1].definition.entities.find_all{|f|
					f.is_a?(Sketchup::Face)
				}

				targets = members.map{|gc|
					pm = VBO::ShapeForge::ForgeElement.new(gc)

					rays = pm.caps.map{|c|
						c.values.map{|c|
							c.transform(gc.transformation)
						}
					}

					intersect = rays.each_with_index.map{|ray, i|

						faces.map{|f|

							inter = Geom.intersect_line_plane(
								ray,
								[
									f.vertices[0].position.transform(trans),
									f.normal.transform(trans)
								]
							)
							if inter && ray[0].distance(inter) > 0.001 && ray[1].length > 0 && ray[0].vector_to(inter).parallel?(ray[1]) && f.classify_point(inter.transform(trans.inverse)) != 16

								[ray[0], inter, inter.distance(ray[0]), i, pm]
							else
								nil
							end
						}.reject{|x| x.nil?}.min_by{|c| c[2]}

					}.reject{|x| x.nil?}
					[
						gc,
						intersect
					]
				}.to_h
				#puts Time.now - t
				targets
			end

			def onKeyUp(key, repeat, flags, view)

				case key
				when 16
					if @state == :select_caps
						@state = @last_state
						@caps.keys.each{|k|
							if @caps[k].empty?
								@caps.delete(k)
								Sketchup.active_model.selection.remove(k)
							end
						}
						@last_state = nil
					else
						@last_state = @state
						@state = :select_caps
						@fix_solid = @solid if @solid
						# @caps = caps_lines(@fix_solid)
					end
				when 13
					do_trim @fix_solid
					reset(view)
				end
				onMouseMove(@pos[0],*@pos[1], view)
			end

			def onMouseMove(flags,x,y,view)
				ph = view.pick_helper
				ph.do_pick(x, y)
				@path = ph.path_at(0)
				@best_picked = ph.best_picked
				@best_picked = nil if !Identify.profile_member?(@best_picked) || @fix_solid.to_a.include?(@best_picked)
				#puts "#{@path}"
				if @path
					@pos = [flags,[x,y]]
				else
					ip1 = view.inputpoint x,y
					edge = ip1.edge
					face = ip1.face
					@path = nil
					@path =  ip1.instance_path.to_a if edge
					@path =  ip1.instance_path.to_a if face
					@path[-1] = @path[-1].edges[0] if @path && @path[-1].is_a?(Sketchup::Vertex)
				end

				@pos = [flags,[x,y]]
				@solid = nil
				sel = self.selected

				if @path
					@trans = Sketchup::InstancePath.new(@path).transformation

					case @state
					when :select_solid
						index = @path.index{|c|
							c.respond_to?(:manifold?) && c.manifold? && !sel.include?(c)
						}
						@solid = @path[0..index] if index
					when :select_members
						@caps = caps_lines(@fix_solid) unless @caps
					when :select_caps
						caps = caps_lines(@fix_solid)
						if caps
							@hovered_cap = caps_lines(@fix_solid).values.flatten(1).find{|c| view.screen_coords(c[0]).distance([x,y,0]) <= 15 * UI.scale_factor}
						end
					end
				end

				view.invalidate
			end

			def draw(view)
				sel = selected
				case @state
				when :one_by_one
					# Sketchup.set_status_text "| #{@state}"
					DRAWVIEW.draw_instance_ref(@solid.to_a, @color, view, true) if @path

				when :multiple
					# Sketchup.set_status_text "| #{@state}"
					DRAWVIEW.draw_instance_ref(@solid.to_a, @color, view, true) if @path
				when :select_solid
					unless sel.empty?
						Sketchup.set_status_text "Click on solid to trim selected members to solid. Shift : Toggle Select Caps Mode"# + "| #{@state}"
					else
						Sketchup.set_status_text "Click to set a solid cutter"# + "| #{@state}"
					end
					DRAWVIEW.draw_instance_ref(@solid, @color, view, true) if @path
					cps = caps_lines(@solid)
					# puts "cps: #{cps}"
					if cps
						cps.each{|k,v|
							pm = VBO::ShapeForge::ForgeElement.new(k)
							if pm.chain.length > 2
								v.each{|c|
									DRAWVIEW.draw_arrow2d(view, c[0], c[1], Sketchup::Color.new('red'))

									pl = pm.project_to_mesh(@solid,[c[3]])
									view.line_stipple = ''
									view.line_width = 2
									pl.each{|ppl|
										view.draw(GL_LINE_STRIP, ppl.map{|c| c[1]}) if ppl.length > 1
										# view.draw_points(ppl, 5 * UI.scale_factor, 1, Sketchup::Color.new('red'))
									}
								}
							else
								c = v.min_by{|c| c[2]}
								DRAWVIEW.draw_arrow2d(view, c[0], c[1], Sketchup::Color.new('red'))

								pl = pm.project_to_mesh(@solid,[c[3]])
								view.line_stipple = ''
								view.line_width = 2
								pl.each{|ppl|
									view.draw(GL_LINE_STRIP, ppl.map{|c| c[1]}) if ppl.length > 1
									# view.draw_points(ppl, 5 * UI.scale_factor, 1, Sketchup::Color.new('red'))
								}
							end
						}

					end

				when :select_members
					Sketchup.set_status_text "Click on member to select. Enter / Click on fixed face to trim selected members to solid"# + "| #{@state}"
					DRAWVIEW.draw_instance_ref(@fix_solid, @color, view, true)

					if @best_picked
						mem = VBO::ShapeForge::ForgeElement.new(@best_picked)
						color = Sketchup::Color.new('magenta')
						view.drawing_color = color
						# mem.draw_view(0,-1,view)
						VBO::ShapeForge::DRAWVIEW.draw_path3d(
							view,
							mem.chain.path.map{|c|
								c.transform(mem.transformation)
							},
							color
						)
					end
					@caps.to_a.each{|k,v|
						if v[0][4].chain.path.length == 2
							c = v.min_by{|vv| vv[2]}
							DRAWVIEW.draw_arrow2d(view, c[0], c[1], Sketchup::Color.new('red'))
						else
							v.each{|c|
								DRAWVIEW.draw_arrow2d(view, c[0], c[1], Sketchup::Color.new('red'))
							}
						end
					}

				when :select_caps
					Sketchup.set_status_text "Click on member to select. Click on member's cap to toggle select cap. Enter / Click on fixed face to trim selected members to solid" #+ "| #{@state}"
					DRAWVIEW.draw_instance_ref(@fix_solid, @color, view, true)

					if @best_picked && !@hovered_cap
						mem = VBO::ShapeForge::ForgeElement.new(@best_picked)
						color = Sketchup::Color.new('magenta')
						view.drawing_color = color
						# mem.draw_view(0,-1,view)
						VBO::ShapeForge::DRAWVIEW.draw_path3d(
							view,
							mem.chain.path.map{|c|
								c.transform(mem.transformation)
							},
							color
						)
					end

					@caps.each{|k,v|
						v.each{|c|
							DRAWVIEW.draw_arrow2d(view, c[0], c[1], Sketchup::Color.new('black'))
						}
					} if @caps
					if @caps && !@caps.empty? && !@caps.values.flatten(1).empty?
						view.draw_points(@caps.values.flatten(1).map{|c| c[0]},8 * UI.scale_factor, 1, Sketchup::Color.new('red'))

						view.draw_points([@hovered_cap[0]] ,15 * UI.scale_factor, 2, Sketchup::Color.new('red')) if @hovered_cap
					end
				end
			end
		end

		class PickTool
			attr_accessor :paintcolor, :path, :pos, :action
			def initialize(type)
				type = [type] unless type.is_a?(Array)
				@type = type
				@paintcolor = Sketchup::Color.new(255, 0, 0)
				@paintcolor.alpha = 150
				@action = nil

			end
			def getExtents
				bb = Sketchup.active_model.bounds
				return bb
			end
			def draw(view)
				DRAWVIEW.draw_face_ref( @path, @paintcolor,view) if @type.include?(Sketchup::Face)
				DRAWVIEW.draw_edge_ref( @path, @paintcolor,view) if @type.include?(Sketchup::Edge)
				if @type.include?(Sketchup::Group) || @type.include?(Sketchup::ComponentInstance)
					DRAWVIEW.draw_edges_ref( @path[0..@path.length-1], @paintcolor,view)
					DRAWVIEW.draw_instance_ref( @path, @paintcolor,view)
				end
			end
			def onMouseMove(flags, x, y, view)
				ph = view.pick_helper
				ph.do_pick(x, y)
				@path = ph.path_at(0)
				@pos = [flags,[x,y]]
				view.invalidate
			end
			def onLButtonDown(flags, x, y, view)
				@action.call(self) if @action
			end
		end

		class PickMaterial
			attr_accessor :path, :pos, :action
			def initialize(action = ->(tool) {puts tool.to_s})
				@tool_fc = PickTool.new(Sketchup::Face)
				@action = action
				path_to_images = File.join(File.dirname(__FILE__), 'images/cursors')
				@cursor_id = UI.create_cursor(File.join(path_to_images,"get_material.svg"), 0, 36)
				reset
			end
			def paintcolor=(color)
				@paintcolor = color
				@tool_fc.paintcolor = color
			end

			def reset
				UI.set_cursor(@cursor_id)
			end

			def onCancel(view, reason)
				Sketchup.active_model.tools.pop_tool
			end
			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end

			def onMouseMove(flags, x, y, view)
				@tool_fc.onMouseMove(flags, x, y, view)
				view.invalidate
			end
			def deactivate(view)
				view.invalidate
			end

			def getExtents
				bb = Sketchup.active_model.bounds
				return bb
			end

			def get_mat
				path = [] + @tool_fc.path.to_a
				path = path.map{|c| DRAWVIEW.display_name(c.material)}
				path.pop until path[-1] != "Default" || path.empty?
				mat = path.empty? ? "Default" : path[-1]
				mat.gsub('&lt', '<')
				mat
			end

			def draw(view)
				if @tool_fc.path && @tool_fc.path[-1].is_a?(Sketchup::Face )
					@tool_fc.draw(view)
					DRAWVIEW.draw_textbox(view,  @tool_fc.pos[1], get_mat)
				end
			end
			def onLButtonDown(flags, x, y, view)
				mod = Sketchup.active_model
				@action.call(get_mat) if @tool_fc.path
			end
		end

		class PickGC
			attr_accessor :action
			def initialize(action = ->(tool) {puts tool}, condition = -> (a) {true})
				@tool_fc = PickTool.new([Sketchup::Group, Sketchup::ComponentInstance])
				@selection = [] + Sketchup.active_model.selection.to_a
				@selection = Sketchup.active_model.entities if @selection.empty?
				@action = action

				@condition = condition
				path_to_images = File.join(File.dirname(__FILE__), 'images/cursors')
				@cursor_id = UI.create_cursor(File.join(path_to_images,"get_definition.svg"), 0, 36)

				reset
			end
			def paintcolor=(color)
				@tool_fc.paintcolor = color
			end
			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end
			def reset
				UI.set_cursor(@cursor_id)
				@level = -1
			end
			def onMouseMove(flags, x, y, view)
				@tool_fc.onMouseMove(flags, x, y, view)
				view.invalidate
			end
			def deactivate(view)
				view.invalidate
			end
			def getExtents
				bb = Sketchup.active_model.bounds
				return bb
			end
			def onMouseWheel(flags, delta, x, y, view)
				ph = view.pick_helper
				ph.do_pick(x, y)
				path = ph.path_at(0)
				return false if !path
				@level = path.length - 1 if @level == -1 || @level >  path.length - 1
				return false if !(path.to_a[@level].is_a?(Sketchup::Group) || path.to_a[@level].is_a?(Sketchup::ComponentInstance) || path.to_a[@level].is_a?(Sketchup::Face) || path.to_a[@level].is_a?(Sketchup::Edge))

				if flags != 0
					Sketchup.set_status_text flags.to_s
					@level += delta
					@level = 0 unless @level > 0
					@level =  path.length - 1 unless @level < path.length - 1
					view.invalidate
					return true
				else
					return false
				end
			end

			def draw(view)
				if @tool_fc.path
					@level = @tool_fc.path.length - 1 if @level == -1 || @level >  @tool_fc.path.length - 1
					return if @tool_fc.path.to_a[@level].to_s.include?('Deleted')
					if @tool_fc.path.to_a[@level].is_a?(Sketchup::Group) || @tool_fc.path.to_a[@level].is_a?(Sketchup::ComponentInstance)
						definition = @tool_fc.path[@level].definition
					elsif @tool_fc.path.to_a[@level].is_a?(Sketchup::Edge) || @tool_fc.path.to_a[@level].is_a?(Sketchup::Face)
						if @tool_fc.path.to_a[@level].parent == Sketchup.active_model
							return
						else
							definition = @tool_fc.path[@level-1].definition
						end
					else
						return
					end
					Sketchup.set_status_text("Pick to get entity's definition. Shift + Mouse Wheel to adjust the active level")
					mess = "   #{definition.name}"
					if @tool_fc.path.to_a[@level].is_a?(Sketchup::Face) || @tool_fc.path.to_a[@level].is_a?(Sketchup::Edge)
						DRAWVIEW.draw_instance_ref( @tool_fc.path[0..@level-1],  @tool_fc.paintcolor,view)
					else
						DRAWVIEW.draw_instance_ref( @tool_fc.path[0..@level],  @tool_fc.paintcolor,view)
					end
					DRAWVIEW.draw_textbox(view, @tool_fc.pos[1], mess)
				end
			end
			def onCancel(view, reason)
				Sketchup.active_model.tools.pop_tool
			end
			def onLButtonDown(flags, x, y, view)
				mod = Sketchup.active_model
				if @tool_fc.path.nil?

				else
					if @tool_fc.path.to_a[@level].is_a?(Sketchup::Group) || @tool_fc.path.to_a[@level].is_a?(Sketchup::ComponentInstance)
					definition = @tool_fc.path[@level].definition
					else
						if @tool_fc.path.to_a[@level].parent == Sketchup.active_model
							return
						else
							definition = @tool_fc.path[@level-1].definition
						end
					end
					@action.call(definition)
				end
			end
		end

		class PickLayer
			attr_accessor :action
			def initialize(action = ->(tool) {puts tool}, condition = -> (a) {true})
				@tool_fc = PickTool.new([Sketchup::Group, Sketchup::ComponentInstance])
				@selection = [] + Sketchup.active_model.selection.to_a
				@selection = Sketchup.active_model.entities if @selection.empty?
				@action = action

				@condition = condition
				path_to_images = File.join(File.dirname(__FILE__), 'images/cursors')
				@cursor_id = UI.create_cursor(File.join(path_to_images,"get_layer.svg"), 0, 36)
				@tool_fc.paintcolor = Sketchup::Color.new('DarkOrange')
				reset
			end
			def paintcolor=(color)
				@level = -1
				@tool_fc.paintcolor = color
			end
			def reset

			end

			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end

			def getExtents
				bb = Sketchup.active_model.bounds
				return bb
			end
			def onMouseMove(flags, x, y, view)
				@tool_fc.onMouseMove(flags, x, y, view)
				view.invalidate
			end
			def deactivate(view)
				view.invalidate
			end

			def onMouseWheel(flags, delta, x, y, view)
				ph = view.pick_helper
				ph.do_pick(x, y)
				path = ph.path_at(0)
				return false if !path
				@level = path.length - 1 if @level == -1 || @level >  path.length - 1
				return false if !(path.to_a[@level].is_a?(Sketchup::Group) || path.to_a[@level].is_a?(Sketchup::ComponentInstance) || path.to_a[@level].is_a?(Sketchup::Face) || path.to_a[@level].is_a?(Sketchup::Edge))

				if flags != 0
					Sketchup.set_status_text flags.to_s
					@level += delta
					@level = 0 unless @level > 0
					@level =  path.length - 1 unless @level < path.length - 1
					view.invalidate
					return true
				else
					return false
				end
			end

			def draw(view)
				if @tool_fc.path
					@level = @tool_fc.path.length - 1 if @level == -1 || @level > @tool_fc.path.length - 1
					return if @tool_fc.path.to_a[@level].to_s.include?('Deleted')
					if @tool_fc.path[@level].respond_to?(:layer)
						layer = @tool_fc.path[@level].layer
						Sketchup.set_status_text("Pick to get entity's definition. Shift + Mouse Wheel to adjust the active level")
						mess = "   #{Sketchup.version.to_i.ceil > 19 ? layer.name.gsub('Layer0','Untagged') : layer.name}"
						if @tool_fc.path.to_a[@level].is_a?(Sketchup::Face) || @tool_fc.path.to_a[@level].is_a?(Sketchup::Edge)
							DRAWVIEW.draw_instance_ref( @tool_fc.path[0..@level],  @tool_fc.paintcolor,view)
						else
							DRAWVIEW.draw_instance_ref( @tool_fc.path[0..@level+1],  @tool_fc.paintcolor,view)
						end
						DRAWVIEW.draw_textbox(view, @tool_fc.pos[1], mess)
					end
				end
			end
			def onCancel(view, reason)
				Sketchup.active_model.tools.pop_tool
			end
			def onLButtonDown(flags, x, y, view)
				mod = Sketchup.active_model
				if @tool_fc.path.nil?
				else
					layer = @tool_fc.path[@level].respond_to?(:layer) ? @tool_fc.path[@level].layer : nil
					@action.call(layer)
				end
			end
		end

		class PickProfile
			def initialize(action = ->(tool) {puts tool.to_s})
				@tool_fc = PickTool.new([Sketchup::Group, Sketchup::ComponentInstance,Sketchup::Face])
				@action = action
				path_to_images = File.join(File.dirname(__FILE__), 'images/cursors')
				@cursor_id = UI.create_cursor(File.join(path_to_images,"get.svg"), 0, 36)
				reset
			end
			def paintcolor=(color)
				@paintcolor = color
				@tool_fc.paintcolor = color
			end
			def getExtents
				bb = Sketchup.active_model.bounds

				return bb
			end
			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end

			def reset
				UI.set_cursor(@cursor_id)
			end

			def onCancel(view, reason)
				Sketchup.active_model.tools.pop_tool
			end

			def onMouseMove(flags, x, y, view)
				@tool_fc.onMouseMove(flags, x, y, view)
				view.invalidate
			end
			def deactivate(view)
				view.invalidate
			end
			def draw(view)
				if @tool_fc.path
					mem = @tool_fc.path.find{|c| VBO::ShapeForge::Identify.profile_member?(c)}
					if mem
						index = @tool_fc.path.index(mem)
						DRAWVIEW.draw_instance_ref( @tool_fc.path[0..index],  @tool_fc.paintcolor,view)
						member = VBO::ShapeForge::ForgeElement.new(mem)
						@profile = member.profile
						@profile.preview2(VBO::ShapeForge.assembly_dialog.dialog)
						DRAWVIEW.draw_textbox(view,  @tool_fc.pos[1], @profile.name.gsub("*_*", " ").gsub("%20", " "))
					elsif @tool_fc.path[-1].is_a?(Sketchup::Face )
						@tool_fc.draw(view)
						@profile = VBO::ShapeForge::Shape.new(@tool_fc.path[-1])
						@profile.preview2(VBO::ShapeForge.assembly_dialog.dialog)
						DRAWVIEW.draw_textbox(view,  @tool_fc.pos[1], @profile.name.gsub("*_*", " ").gsub("%20", " "))
					end
				end
			end
			def onLButtonDown(flags, x, y, view)
				@action.call(@profile) if @tool_fc.path
			end
		end

		class PickForgeStructure
			def initialize(action = ->(tool) {puts tool.to_s})
				@tool_fc = PickTool.new([Sketchup::Group, Sketchup::ComponentInstance,Sketchup::Face])
				@action = action
				path_to_images = File.join(File.dirname(__FILE__), 'images/cursors')
				@cursor_id = UI.create_cursor(File.join(path_to_images,"get.svg"), 0, 36)
				reset
			end
			def paintcolor=(color)
				@paintcolor = color
				@tool_fc.paintcolor = color
			end

			def getExtents
				bb = Sketchup.active_model.bounds

				return bb
			end

			def reset
				@ass = nil
				UI.set_cursor(@cursor_id)
			end

			def onCancel(view, reason)
				@action.call(nil)
			end
			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end

			def onMouseMove(flags, x, y, view)
				@tool_fc.onMouseMove(flags, x, y, view)
				view.invalidate
			end
			def deactivate(view)
				view.invalidate
			end
			def draw(view)
				if @tool_fc.path
					mem = @tool_fc.path.find{|c| VBO::ShapeForge::Classify.assembly?(c)}
					if mem
						index = @tool_fc.path.index(mem)
						DRAWVIEW.draw_instance_ref( @tool_fc.path[0..index],  @tool_fc.paintcolor,view)
						@ass = VBO::ShapeForge::ForgeStructure.get(mem)
						DRAWVIEW.draw_textbox(view,  @tool_fc.pos[1], @ass.name)
					end
				end
			end
			def onLButtonDown(flags, x, y, view)
				@action.call(@ass) if @tool_fc.path
			end
		end

		class SelHilight
			attr_accessor :path
			def initialize(entities, path = nil)
				@path = path
				@picktool = HilightEntities.new(entities)
			end
			def activate
			end
			def deactivate(view)
					view.invalidate
			end

			def getExtents
				bb = Sketchup.active_model.bounds
				return bb
			end

			def draw(view)
				@picktool.draw(view)
				if @path
					VBO::ShapeForge::DRAWVIEW.draw_path3d(view, @path, Sketchup::Color.new('red'))
				end
			end
			def onMouseMove(flags, x, y, view)
					@picktool.onMouseMove(flags, x, y, view)
					view.invalidate
			end
			def onLButtonDown(flags, x, y, view)
					Sketchup.active_model.tools.pop_tool
			end
			def reverse_path
				@path.reverse!
				onMouseMove(@picktool.pos[0], @picktool.pos[1][0], @picktool.pos[1][0], Sketchup.active_model.active_view)
			end

			def close_path
				if @path[0] == @path[-1]
          return if @path.nil? || @path.length < 4
          @path.pop
        else
          return if @path.nil? || @path.length < 3
          @path << @path[0]
        end
				onMouseMove(@picktool.pos[0], @picktool.pos[1][0], @picktool.pos[1][0], Sketchup.active_model.active_view)
			end
		end

		class HilightEntities
			attr_accessor :maxent, :entities, :color, :pos
			def initialize(entities, color = Sketchup::Color.new('magenta'), maxent = 20000)
					@entities = entities
					@maxent = maxent
					@color = color
					Sketchup.active_model.active_view.invalidate
			end
			def activate
			end
			def display_typename(key)
					if key.nil?
							return 'Material'
					else
							return key.typename
					end
			end
			def deactivate(view)
					view.invalidate
			end

			def highlight(*ents)

			end

			def get_draw_face(face, tr, view)
        loops = []
        triangles = []
        face.loops.each{|lo|
            points3d = lo.vertices.map{|c| c.position.transform(tr)}
            points2d = points3d.map{|c| view.screen_coords(c)}
            loops += slicing(points2d)
        }

        mesh = face.mesh(0)
        ps   = (1..mesh.count_polygons).map { |i|
        mesh.polygon_points_at(i).map{ |p|
            view.screen_coords(p.transform(tr))
        }
        }.flatten
        triangles = ps
        {loops: loops, triangles: triangles}
    end

    def draw_face(face, tr,color, view)
        draws =  get_draw_face(face, tr, view)

        view.line_width=3
        view.line_stipple = ""
        color.alpha = 255
        view.drawing_color = color
        view.draw2d(GL_LINES, draws[:lines])

        color.alpha = 60
        view.drawing_color = color
        view.draw2d(GL_TRIANGLES, draws[:triangles])
    end

    def get_draw_boundingbox(view, bounds, t)
        lines = []
        quads = []

        if bounds.width == 0 || bounds.height == 0 || bounds.depth == 0
            if bounds.width == 0
                ps  = [0, 2, 6, 4].map { |i| bounds.corner(i).transform!(t) }
            elsif bounds.height == 0
                ps  = [0, 1, 5, 4].map { |i| bounds.corner(i).transform!(t) }
            elsif bounds.depth == 0
                ps  = [0, 1, 3, 2].map { |i| bounds.corner(i).transform!(t) }
            end
            # Draw lines
            lines = slicing(ps.map { |p| view.screen_coords(p) })
            # Draw polygons
            quads = ps
            quadstrip = []
        else
            ps  = (0..7).map { |i| bounds.corner(i).transform!(t) }

            lines = [0,1,0,4,0,2,7,6,7,3,7,5,1,3,1,5,4,6,4,5,2,3,2,6].map { |p| view.screen_coords(ps[p]) }
            quads = [0,2,3,1,2,3,7,6,6,7,5,4,4,5,1,0, 0,2,6,4,1,3,7,5].map{|c| view.screen_coords ps[c]}
        end
        {lines: lines, quads_3d: quads}
    end
		def self.draw_boundingbox(view, bounds, color, t)
			draws = get_draw_boundingbox(view, bounds, t)
			view.line_width=1
			view.line_stipple = ""
			color.alpha = 255
			view.drawing_color = color
			view.draw2d(GL_LINES, draws[:lines])

			color.alpha = 50
			view.drawing_color = color
			view.draw2d(GL_QUADS, draws[:quads_3d])
		end

		def self.get_draw_edge(edge, tr, view)
			points3d = edge.vertices.map{|c| c.position.transform(tr)}
			points2d = points3d.map{|c| view.screen_coords(c)}
			points2d
		end

		def self.draw_edge(edge, tr, color, view)
			points3d = edge.vertices.map{|c| c.position.transform(tr)}
			points2d = points3d.map{|c| view.screen_coords(c)}

			view.line_width= 5
			view.line_stipple = "-"
			color.alpha = 170
			view.drawing_color = color
			view.draw2d(GL_LINES,points2d)
			view.line_width=5
			view.line_stipple = "-"
			color.alpha = 200
			view.drawing_color = color
			view.draw(GL_LINES,points3d)
		end

			def draw(view)
					if @entities.length <= @maxent && !@entities[-1].to_s.include?('Deleted')
							lines =  {
									lines: [],
									color: nil
							}
							faces = {
									lines: [],
									triangles: [],
									color: nil
							}
							instances = {
									lines: [],
									quads_3d: [],
									color: nil
							}
							@entities.each{|ent|
									entity = ent[-1]
									transformation = Sketchup::InstancePath.new(ent).transformation
									case display_typename(entity)
									when 'Edge'
											#VBO::Reports.draw_edge(entity, transformation, @color, view)
											f = get_draw_edge(entity, transformation, view)
											lines[:lines] += f
											lines[:color] = @color
									when 'Face'
											#VBO::Reports.draw_face(entity, transformation, @color, view)
											f = get_draw_face(entity, transformation, view)
											faces[:lines] += f[:loops]
											faces[:triangles] += f[:triangles]
											faces[:color] = @color
									when 'Group', 'ComponentInstance'
										member = VBO::ShapeForge::Identify.profile_member?(entity)
										ass = VBO::ShapeForge::Identify.assembly?(entity)
										if member
											@color.alpha =200
											view.drawing_color = @color
											view.line_width = 2
											member = VBO::ShapeForge::ForgeElement.new(entity)
											member.draw_view(
												0,
												-1,
												view,
												transformation
											)
										else

											bbs =  entity.definition.bounds

											ii = get_draw_boundingbox(view, bbs, transformation)
											instances[:lines] += ii[:lines]
											instances[:quads_3d] += ii[:quads_3d]
											instances[:color] = @color
										end
									end
							}

							if lines[:color]
									color = lines[:color]
									view.line_width = 3
									color.alpha =80
									view.drawing_color = color

									view.draw2d(GL_LINES, lines[:lines])
							end

							if faces[:color]
									color = faces[:color]
									color.alpha =255
									view.drawing_color = color
									view.line_width = 2
									view.draw2d(GL_LINES, faces[:lines])
									Sketchup.set_status_text "faces triangles #{faces[:triangles].length}"
									if faces[:triangles].length < 2000
											color.alpha = 60
											view.drawing_color = color
											view.draw2d(GL_TRIANGLES, faces[:triangles])
									end
							end

							# instances
							if instances[:color]
									color = instances[:color]
									color.alpha =255
									view.drawing_color = color
									view.line_width = 2
									view.draw2d(GL_LINES, instances[:lines])
									if instances[:quads_3d].length < 2000
											color.alpha = 30
											view.drawing_color = color
											view.draw2d(GL_QUADS, instances[:quads_3d])
									end
							end

					else
							# view.draw_text(@pos[1], "Data's too large to hilight", {
							# 		font: "Arial",
							# 		size: 12 * UI.scale_factor,
							# 		bold: true,
							# 		color: Sketchup::Color.new("red"),
							# 		align: TextAlignCenter
							# }) if @pos
					end
			end
			def onMouseMove(flags, x, y, view)
					ph = view.pick_helper
					ph.do_pick(x, y)

					@pos = [flags,[x,y]]

			end
		end

		class ObjPath
			attr_accessor :path, :closed_path, :last_point, :gc
			def initialize(snap = nil, closed_path = false)
				@path = []
				@closed_path = closed_path
			end
			def debug(message)
        VBO::ShapeForge.debug(message)
      end
			def draw(view)
				unless @path.empty?
					if @closed_path
						draw_loop(view)
					else
						draw_strip(view)
					end
				end
			end

			def draw_strip(view)
				view.set_color_from_line(@path[-1], @last_point)
				view.draw(GL_LINE_STRIP, @path + [@last_point])
			end

			def draw_loop(view)
				view.set_color_from_line(@path[-1], @last_point)
				view.draw(GL_LINE_LOOP, @path + [@last_point])
			end

			def create_geometry(entities = Sketchup.active_model.active_entities)
				unless @path.empty?
				  @gc.erase! if @gc
					@gc = entities.add_group
					if @closed_path
						create_geometry_loop(@gc.entities)
					else
						create_geometry_strip(@gc.entities)
					end
					@gc
				end
			end

			def create_geometry_strip(entities)
			  # debug(@path.to_s)
				entities.add_edges(@path)
			end
			def create_geometry_loop(entities)
				entities.add_edges(@path + [@path[0]])
			end

			def add_point(pt)
				@path << pt
			end
			def insert_point_at(pt,index)
				@path.insert(pt, index)
			end
			def delete_point_at(index)
				@path.delete_at(index)
			end
			def move_point(index,vector)
				@path[index] = @path[index].offset(vector)
			end
			def close_path
				@closed_path = true
			end
			def open_path
				@closed_path = false
			end
			def merge(points)
				points = points.sort
				if points.length == 2 &&
				(points[0] - points[1]).abs == 1
					p1 = @path[points[0]]
					p2 = @path[points[1]]
					vec = p1.vector_to(p2)
					vec.length = vec.length / 2
					new_point = p1.offset(vec)
					@path.slice!(*points)
					@path.insert(points[0], new_point)
				end
			end
			def kill
				@gc = nil
			end
		end

		class ClickClickTool
			attr_accessor :obj
			def initialize(obj)
				@ip1 = nil
				@ip2 = nil
				@xdown = 0
				@ydown = 0
				@obj = obj
			end

			def activate
				@ip1 = Sketchup::InputPoint.new
				@ip2 = Sketchup::InputPoint.new
				@ip = Sketchup::InputPoint.new
				@drawn = false
				Sketchup::set_status_text "Length", SB_VCB_LABEL
				reset(nil)
				@edit_transform = axes_edit_transform
			end

			def onCancel(flag, view)
				case flag
				when 2
					Sketchup.active_model.tools.pop_tool
					Sketchup.active_model.select_tool nil
					view.invalidate if @drawn
				else
					if @state == 0
						Sketchup.active_model.tools.pop_tool
						Sketchup.active_model.select_tool nil
					end
					self.reset(view)
				end
			end

			def reset(view)
				@state = 0
				Sketchup::set_status_text("Select first point.", SB_PROMPT)
				@ip1.clear
				@ip2.clear
				@ip_lock=nil
				@ctrl = false
				if( view )
					view.tooltip = nil
					view.invalidate if @drawn
				end
				@obj.path = []
				@drawn = false
			end

			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end

			def getExtents
				bb = Sketchup.active_model.bounds
				bb.add @ip1.position if @ip1.valid?
				bb.add @ip2.position if @ip2.valid?
				return bb
			end

			def deactivate(view)
				view.invalidate if @drawn
			end

			#------------------------Keyboard Events--------------------------------
			def onKeyDown(key, repeat, flags, view)
				if( key == CONSTRAIN_MODIFIER_KEY )
					@shift_down_time =true
					if( view.inference_locked? )
						view.lock_inference
					elsif( @state == 0 && @ip1.valid? )
						view.lock_inference @ip1
					elsif( @state == 1 && @ip2.valid? )
						@p_shift=@ip.position
						view.lock_inference @ip2, @ip1
					end
				elsif key==VK_UP
					view.lock_inference if view.inference_locked?
					if @ip.valid? && @state>0
						p =  @ip1.position
						p1 = p + @edit_transform.zaxis
						ip1 = Sketchup::InputPoint.new(p1)
						view.lock_inference ip1,@ip
						@ip_lock=ip1.position
						@ip2.copy! ip1
					end
				elsif key==VK_LEFT
					view.lock_inference if view.inference_locked?
					if @ip.valid? && @state>0
						p1=@ip1.position + @edit_transform.yaxis
						ip1 = Sketchup::InputPoint.new(p1)
						view.lock_inference ip1,@ip
						@ip_lock=ip1.position
						@ip2.copy! ip1
					end
				elsif key==VK_RIGHT
					view.lock_inference if view.inference_locked?
					if @ip.valid? && @state>0
						p1=@ip1.position + @edit_transform.xaxis
						ip1 = Sketchup::InputPoint.new(p1)
						view.lock_inference ip1,@ip
						@ip_lock=ip1.position
						@ip2.copy! ip1
					end
				elsif key == 17
				end
			end

			def onKeyUp(key, repeat, flags, view)
				case key
					when 27		#	Escape key
					when 13		#	Enter key


					when CONSTRAIN_MODIFIER_KEY 		#	Shift key
						@shift_down_time=nil
						@p_shift=nil
						view.lock_inference
						view.invalidate
					when COPY_MODIFIER_KEY 		#	Alt/Option on Mac, Ctrl on PC
					when ALT_MODIFIER_KEY 		#	Command on Mac, Alt on PC

					when 9		#	Tab key

					when 8		#	Backspace key

					when 38		#	Up key
					when 40		#	Down key

					when 37		#	Left key
					when 39		#	Right key

					when 36		#	Home key
					when 35		#	End key
					else
				end

			end

			def getMenu(menu, flags, x, y, view)
			end

			#------------------------onMouseMove-----------------------------------
			def onMouseMove(flags, x, y, view)

				@pick_ray = view.pickray(x,y)

				ph = view.pick_helper
				ph.do_pick(x, y)
				@path = ph.path_at(0)

				if( @state == 0 )
					@ip.pick view, x, y
					if( @ip != @ip1 )
						view.tooltip = @ip.tooltip
						view.invalidate if( @ip.display? or @ip1.display? )
						@ip1.copy! @ip
					end
				else # state == 1
					@ip.pick view, x, y, @ip1
					Sketchup::set_status_text "Length", SB_VCB_LABEL

					view.tooltip = @ip.tooltip if( @ip.valid? )
					if @shift_down_time && @p_shift && @ip!=@ip1 &&   @ip2!=@ip1
						p2_line = @ip.position.project_to_line([@ip1.position,@p_shift])
						@ip2.copy!(p2_line ? Sketchup::InputPoint.new(p2_line) : @ip)
					else
						@ip2.copy! @ip
					end
					if( @ip2.valid? )
						length = @ip1.position.distance(@ip2.position)
						Sketchup::set_status_text length, SB_VCB_VALUE
						@obj.last_point = @ip2.position
					end
				end
				if @path.nil?
					edge = @ip.edge
					face = @ip.face
					@path =  @ip.instance_path.to_a if edge
					@path =  @ip.instance_path.to_a if face
					if @path && @path[-1].is_a?(Sketchup::Vertex)
						@path[-1] = @path[-1].edges[0]
					end
				end
				@path = nil if @path && ![
					Sketchup::ComponentInstance,
					Sketchup::Group,
					Sketchup::Face,
					Sketchup::Edge,
					Sketchup::ConstructionLine,
					Sketchup::ConstructionPoint,
					Sketchup::SectionPlane,
					Sketchup::Image
				].include?(@path[-1].class)
				@pos = [flags,[x,y]]

				view.invalidate
			end

			def draw(view)
				if @ip && @ip.valid?
					if @ip.display?
						@ip.draw(view)
					end
				end

				if( @ip1.valid? )
					if( @ip1.display? )
						@ip1.draw(view)  if @state == 0
						@drawn = true
					end
					if( @ip2.valid? )
						Sketchup.set_status_text("Tab -> Alignment. UP -> Add a demo door's opening. DOWN -> Clear Openings.")
						@drawn = true
						if @p_shift && @ip_lock
							p = @p_shift
							p = @ip_lock if @ip_lock
							p2_line=@ip.position.project_to_line([@ip1.position,p])
							view.draw_points p2_line, 7, 2, "red"  if p2_line
							@ip2.copy! Sketchup::InputPoint.new(p2_line)
							view.line_stipple = "."
							view.drawing_color ="blue"
							view.draw_line(@ip.position, @ip2.position)
							view.line_stipple = ""
							view.drawing_color ="black"
						end
						@ip2.draw(view) if( @ip2.display? )
						draw_geometry(view)
					end
				end
			end

			#------------------------onLButtonUp------------------------------------
			def onLButtonUp(flags, x, y, view)
				if( @state == 0 )
					if( @ip1.valid? )
					  @obj.path << @ip1.position
						case flags
						when 0
							@state = 1
							Sketchup::set_status_text "Select second point", SB_PROMPT
							@xdown = x
							@ydown = y
						when 8 #ctrl click
						end
					end
				else
					if( @ip2.valid? )
						case flags
						when 8 #ctrl click
						else
							ip = Sketchup::InputPoint.new @ip2.position
							@obj.path << @ip2.position
							create_geometry(@ip1.position, @ip2.position,view)
							reset(view)

						end
					end
				end
				view.lock_inference
			end

			def onUserText(text, view)
				if @state == 1
					return if not @ip2.valid?
					if text.start_with?('=')
					else
						begin
							value = text.to_l.to_f
							Sketchup::set_status_text value, SB_VCB_VALUE
							pt1 = @ip1.position
							vec = pt1.vector_to(@ip2.position)
							if( vec.length == 0.0 )
								UI.beep
								return
							end
							vec.length = value
							pt2 = pt1 + vec
							@ip2.copy! Sketchup::InputPoint.new(pt2)

							self.create_geometry(pt1, pt2, view)
							@ip1.copy! Sketchup::InputPoint.new(pt2)
						rescue => e
							UI.messagebox(e)
						end
					end
				elsif @state == 0
				end
			end

			private

			def axes_edit_transform
				model=Sketchup.active_model
				return model.axes.transformation if Sketchup.version.to_i>=16
				model.start_operation "get edit transform", true
				ents = model.active_entities
				begin
					g = ents.add_group(ents.add_group)
					t = Geom::Transformation.new(g.transformation.xaxis,g.transformation.yaxis,g.transformation.zaxis,g.transformation.origin)
					g.erase! if g && g.valid? && !g.deleted?
				rescue
					t = model.edit_transform
				end
				model.abort_operation
				return t
			end

			def draw_geometry(view)
				@obj.draw(view)
			end	# method draw_geometry()

			def create_geometry(p1, p2, view)
				Sketchup.active_model.start_operation "Add Geometry", true
				@obj.path = [p1,p2]
				@obj.create_geometry
				Sketchup.active_model.commit_operation
			end
		end

		class PlineTool
			attr_accessor :obj, :action, :snap
			def initialize(obj)
				@ip1 = nil
				@ip2 = nil
				@ip = nil
				@xdown = 0
				@ydown = 0
				@obj = obj
				@action = ->(x){true}
				@snap = ->(view, tool){[nil, nil, nil]}
			end

			def activate
				@ip1 = Sketchup::InputPoint.new
				@ip2 = Sketchup::InputPoint.new
				@ip = Sketchup::InputPoint.new
				@drawn = false
				Sketchup::set_status_text "Length", SB_VCB_LABEL
				reset(nil)
				@edit_transform = axes_edit_transform
			end
			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end

			def deactivate(view)
				view.invalidate
				@action.call(self)
				reset(view)
			end

			def onCancel(flag, view)
				case flag
				when 2
					Sketchup.active_model.tools.pop_tool
					Sketchup.active_model.select_tool nil
					view.invalidate if @drawn
					@action.call(self)
				else
					if @state == 0
						Sketchup.active_model.tools.pop_tool
						Sketchup.active_model.select_tool nil
						view.invalidate if @drawn
						@action.call(self)
					end
					@action.call(self)

					self.reset(view)
				end
			end

			def reset(view)
				@state = 0
				Sketchup::set_status_text("Select first point.", SB_PROMPT)
				@ip.clear
				@ip1.clear
				@ip2.clear
				@ip_lock=nil
				@ctrl = false
				@left_down=false
				@right_down=false
				@down_down=false
				@up_down=false
				if( view )
					view.tooltip = nil
					view.lock_inference if view.inference_locked?
					view.invalidate if @drawn
				end
				@obj.kill
				@obj.path = []
				@drawn = false
			end

			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end

			def getExtents
				bb = Sketchup.active_model.bounds
				bb.add @ip1.position if @ip1.valid?
				bb.add @ip2.position if @ip2.valid?
				bb.add *@obj.path if @obj.path && !@obj.path.empty?
				return bb
			end

			def onKeyDown(key, repeat, flags, view)
				if( key == CONSTRAIN_MODIFIER_KEY )
					@shift_down_time =true
					if( view.inference_locked? )
						view.lock_inference
					elsif( @state == 0 && @ip1.valid? )
						view.lock_inference @ip1
					elsif( @state == 1 && @ip2.valid? )
						@p_shift = @ip1.position.vector_to(@ip.position)
						view.lock_inference @ip2, @ip1
					end
				elsif key==VK_UP || key == VK_DOWN
					view.lock_inference if view.inference_locked?
					if @ip.valid? && @state > 0
						p1 =  @ip1.position
						@p_shift = Z_AXIS
						p2 = @ip.position.project_to_line([@ip1.position, @p_shift])
						temp_ip = Sketchup::InputPoint.new(p2)
						view.lock_inference temp_ip,@ip1
						onMouseMove(@pos[0], *@pos[1], view)
					end
				elsif key==VK_LEFT
					view.lock_inference if view.inference_locked?
					if @ip.valid? && @state > 0
						p1 =  @ip1.position
						@p_shift = Y_AXIS
						p2 = @ip.position.project_to_line([@ip1.position, @p_shift])
						temp_ip = Sketchup::InputPoint.new(p2)
						view.lock_inference temp_ip,@ip1
						onMouseMove(@pos[0], *@pos[1], view)
					end
				elsif key==VK_RIGHT
					view.lock_inference if view.inference_locked?
					if @ip.valid? && @state > 0
						p1 =  @ip1.position
						@p_shift = X_AXIS
						p2 = @ip.position.project_to_line([@ip1.position, @p_shift])
						temp_ip = Sketchup::InputPoint.new(p2)
						view.lock_inference temp_ip,@ip1
						onMouseMove(@pos[0], *@pos[1], view)
					end
				elsif key == 17
				end
			end

			def onKeyUp(key, repeat, flags, view)
				case key
					when 27		#	Escape key
					when 13		#	Enter key
					when CONSTRAIN_MODIFIER_KEY 		#	Shift key
						@shift_down_time=nil
						@p_shift=nil
						view.lock_inference
						view.invalidate
					when COPY_MODIFIER_KEY 		#	Alt/Option on Mac, Ctrl on PC
					when ALT_MODIFIER_KEY 		#	Command on Mac, Alt on PC

					when 9		#	Tab key

					when 8		#	Backspace key

					when 38		#	Up key
					when 40		#	Down key

					when 37		#	Left key
					when 39		#	Right key

					when 36		#	Home key
					when 35		#	End key
					else
				end
				onMouseMove(@pos[0], *@pos[1], view) if @obj.onKeyUp(key, repeat, flags, view)
			end

			def getMenu(menu, flags, x, y, view)
			end

			#------------------------onMouseMove-----------------------------------
			def onMouseMove(flags, x, y, view)

				@pick_ray = view.pickray(x,y)

				ph = view.pick_helper
				ph.do_pick(x, y)
				@path = ph.path_at(0)
				@pos = [flags,[x,y]]
				@path = nil if @path && ![
					Sketchup::ComponentInstance,
					Sketchup::Group,
					Sketchup::Face,
					Sketchup::Edge,
					Sketchup::ConstructionLine,
					Sketchup::ConstructionPoint,
					Sketchup::SectionPlane,
					Sketchup::Image
				].include?(@path[-1].class)

				if( @state == 0 )
					@ip.pick view, x, y
					p_snap = @snap.call(view, self)

					if( @ip != @ip1 )
						view.tooltip = p_snap[0] ? "Snap To Member" : @ip.tooltip
						view.invalidate if( @ip.display? or @ip1.display? )

						@ip1.copy! (p_snap[0] ? Sketchup::InputPoint.new(p_snap[0]) : @ip)
					end
				else # state == 1
					@ip.pick view, x, y, @ip1
					p_snap =@snap.call(view, self)
					Sketchup::set_status_text "Length", SB_VCB_LABEL

					view.tooltip = @ip.tooltip if( @ip.valid? )

					if view.inference_locked?
						p2 = p_snap[0] ? p_snap[0] : @ip.position
						p2_line = p2.project_to_line([@ip1.position, @p_shift])
						@ip2.copy!(p2_line ? Sketchup::InputPoint.new(p2_line) : @ip)
					else
						@ip2.copy! (p_snap[0] ? Sketchup::InputPoint.new(p_snap[0]) : @ip)
					end

					if( @ip2.valid? )
						length = @ip1.position.distance(@ip2.position)
						Sketchup::set_status_text(length, SB_VCB_VALUE)
						@obj.last_point = @ip2.position
					end
				end
				if @path.nil?
					edge = @ip.edge
					face = @ip.face
					@path =  @ip.instance_path.to_a if edge
					@path =  @ip.instance_path.to_a if face
					if @path && @path[-1].is_a?(Sketchup::Vertex)
						@path[-1] = @path[-1].edges[0]
					end
				end



				view.invalidate
			end

			def draw(view)
				case @state
				when 0
					Sketchup.set_status_text("Select the first point. Hold Ctrl for snapping")
				when 1
					Sketchup.set_status_text("Select the next point. Hold Ctrl for snapping. Shift to lock direction. Arrow keys for axis lock.")
				end
				p_snap = @snap.call(view, self)
				if p_snap[0]
					view.draw_points([p_snap[0]], 15 * UI.scale_factor, 2, Sketchup::Color.new('red'))
					DRAWVIEW.draw_path3d(view, p_snap[1], Sketchup::Color.new('magenta'))
				end

				if @ip && @ip.valid? && !p_snap[0]
					if @ip.display?
						@ip.draw(view)
					end
				end

				if( @ip1.valid? )
					if( @ip1.display? )
						@ip1.draw(view)  if @state == 0
						@drawn = true
					end
					if( @ip2.valid? )

						@drawn = true
						if @p_shift && @ip_lock
							fip = Sketchup::InputPoint.new
							fip.pick view, *@pos[1]
							p_snap = @snap.call(view, self)
							p = @p_shift
							p = @ip_lock if @ip_lock
							p2 = p_snap[0] ? p_snap[0] : @ip.position
							p2_line = p2.project_to_line([@ip1.position,p])
							view.draw_points p2_line, 7, 2, "red"  if p2_line
							@ip2.copy! Sketchup::InputPoint.new(p2_line)
							view.line_stipple = "."
							view.drawing_color ="blue"
							view.draw_line(@ip.position, @ip2.position)
							view.line_stipple = ""
							view.drawing_color ="black"
						end
						@ip2.draw(view) if( @ip2.display? )
						draw_geometry(view)
					end
				end
			end

			#------------------------onLButtonUp------------------------------------
			def onLButtonUp(flags, x, y, view)
				if( @state == 0 )
					if( @ip1.valid? )

						case flags
						when 0
							@obj.path << @ip1.position
							@state = 1
							@xdown = x
							@ydown = y
						when ALT_MODIFIER_MASK
							p_snap = @snap.call(view, self)
							@ip1 = p_snap[0] ? Sketchup::InputPoint.new(p_snap[0]) : @ip1
							@obj.path << @ip1.position
							@state = 1
							@xdown = x
							@ydown = y
						end
					end
				else
					if( @ip2.valid? )
						case flags
						when ALT_MODIFIER_MASK
							p_snap = @snap.call(view, self)
							ip =  p_snap[0] ? Sketchup::InputPoint.new(p_snap[0]) :  Sketchup::InputPoint.new(@ip2.position)
							@obj.path << ip.position
							@left_down=@right_down=@up_down=@down_down=false
							create_geometry()
							if ip.valid?
								@ip1.copy! ip
							else
								reset(view)
							end
						else
							ip = Sketchup::InputPoint.new @ip2.position
							@obj.path << @ip2.position
							create_geometry()
							if ip.valid?
								@ip1.copy! ip
							else
								reset(view)
							end
						end
					end
				end
				view.lock_inference
			end

			def onUserText(text, view)
				if @state == 1
					return if not @ip2.valid?
					if text.start_with?('=')
					else
						begin
							value = text.to_l.to_f
							Sketchup::set_status_text value, SB_VCB_VALUE
							pt1 = @ip1.position
							vec = pt1.vector_to(@ip2.position)
							if( vec.length == 0.0 )
								UI.beep
								return
							end
							vec.length = value
							pt2 = pt1 + vec
							@ip2.copy! Sketchup::InputPoint.new(pt2)
							@obj.path << @ip2.position
							self.create_geometry()
							@ip1.copy! Sketchup::InputPoint.new(pt2)
						rescue => e
							UI.messagebox(e)
						end
					end
				elsif @state == 0
				end
			end

			private

			def axes_edit_transform
				model=Sketchup.active_model
				return model.axes.transformation if Sketchup.version.to_i>=16
				model.start_operation "get edit transform", true
				ents = model.active_entities
				begin
					g = ents.add_group(ents.add_group)
					t = Geom::Transformation.new(g.transformation.xaxis,g.transformation.yaxis,g.transformation.zaxis,g.transformation.origin)
					g.erase! if g && g.valid? && !g.deleted?
				rescue
					t = model.edit_transform
				end
				model.abort_operation
				return t
			end

			def draw_geometry(view)
				@obj.draw(view)
			end	# method draw_geometry()

			def create_geometry()
				Sketchup.active_model.start_operation "Add Geometry", true
				@obj.create_geometry()
				Sketchup.active_model.commit_operation
				onMouseMove(@pos[0], *@pos[1], Sketchup.active_model.active_view)
			end
		end

		class PickDistanceGetter
			attr_accessor :align_vector, :action, :ip1, :ip2, :prefix, :snap, :first_point, :state

			def initialize(vec =  nil, snap = [], first_point = nil, pre_length = 0)
				@align_vector = vec
				@ip1 = nil
				@ip2 = nil
				@snap = snap
				@first_point = first_point
				@pre_length = pre_length
			end

			def activate
				@ip1 = Sketchup::InputPoint.new
				@ip2 = Sketchup::InputPoint.new
				@ip = Sketchup::InputPoint.new
				@drawn = false
				reset(nil)
			end

			def reset(view)
				if !@first_point
					@state = 0
					Sketchup::set_status_text("Select first point.", SB_PROMPT)
					@ip1.clear
					@ip2.clear

					@drawn = false
				else
					@state = 1
					Sketchup::set_status_text("Select second point.", SB_PROMPT)
					@ip2.clear
					@ip1 = Sketchup::InputPoint.new(@first_point)
					@drawn = true
				end
				if( view )
					view.tooltip = nil
					view.invalidate if @drawn
				end
			end

			def onSetCursor
				UI.set_cursor(@cursor_id) if @cursor_id
			end

			def getExtents
				bb = Sketchup.active_model.bounds
				bb.add @ip1.position if @ip1.valid?
				bb.add @ip2.position if @ip2.valid?
				return bb
			end
			def deactivate(view)
				view.invalidate if @drawn
			end
			def onCancel(flag, view)
					self.reset(view)
			end
			def onMouseMove(flags, x, y, view)
				@pos = [flags, [x,y]]
				if( @state == 0 )
					@ip.pick view, x, y
					p_snap = @snap.find{|sn|
						view.screen_coords(@ip.position).distance(view.screen_coords(sn)) < 10 * UI.scale_factor
					}
					if( @ip != @ip1 )
						view.tooltip = @ip.tooltip
						view.invalidate if( @ip.display? or @ip1.display? )

						@ip1.copy! (p_snap ? Sketchup::InputPoint.new(p_snap) : @ip)
					end
				else # state == 1
					@ip.pick view, x, y, @ip1
					p_snap = @snap.find{|sn|
						view.screen_coords(@ip.position).distance(view.screen_coords(sn)) < 10 * UI.scale_factor
					}
					if p_snap
						@ip = Sketchup::InputPoint.new(p_snap)
					end
					view.tooltip = @ip.tooltip if( @ip.valid? )
					if @align_vector
						p2_line = @ip.position.project_to_line([@ip1.position,@align_vector])
						@ip2.copy!(p2_line ? Sketchup::InputPoint.new(p2_line) : @ip)
					else
						@ip2.copy! @ip
					end

					if( @ip2.valid? )
						length = @ip1.position.distance(@ip2.position)
						Sketchup::set_status_text length, SB_VCB_VALUE
					end
				end
				view.invalidate
			end

			def onUserText(text, view)
				if @state == 1
					return if not @ip2.valid?
					if text.start_with?('=')
					else
						begin
							value = text.to_l.to_f
							Sketchup::set_status_text value, SB_VCB_VALUE
							pt1 = @ip1.position
							vec = pt1.vector_to(@ip2.position)
							if( vec.length == 0.0 )
								UI.beep
								return
							end
							vec.length = value
							pt2 = pt1 + vec
							@ip2.copy! Sketchup::InputPoint.new(pt2)

							@action.call(self)
						rescue => e
							UI.messagebox(e)
						end
					end
				elsif @state == 0
				end
			end

			def draw(view)

				VBO::ShapeForge::DRAWVIEW.draw_path3d(view, @snap, Sketchup::Color.new("red"))

				if @ip && @ip.valid?
					if @ip.display?
						@ip.draw(view)
					end
				end
				if( @ip1.valid? )
					if( @ip1.display? )
						@ip1.draw(view)  if @state == 0
						@drawn = true
					end
					if( @ip2.valid? )
						@drawn = true
						p1 = @ip1.position
						p2 = @ip2.position


						view.line_stipple = "-"
						view.drawing_color ="blue"
						view.draw_line(@ip.position, p2)

						length = p1.distance(p2)
						if p1.vector_to(p2).dot(@align_vector) < 0
						length = -length
							view.line_stipple = "-"
							dim_color = Sketchup::Color.new("magenta")
							dim_back_color = Sketchup.active_model.rendering_options["BackgroundColor"]
						else
							view.line_stipple = ""
							dim_color = Sketchup::Color.new("white")
							dim_back_color = Sketchup::Color.new("magenta")
						end


						view.line_width = 2
						view.drawing_color ="magenta"

						view.draw2d(GL_LINE_STRIP, [p1, p2].map{|c| view.screen_coords(c)})

						DRAWVIEW.draw_arrow2d(view,p1, p2)
						DRAWVIEW.draw_arrow2d(view,p2, p1)

						@ip2.draw(view) if( @ip2.display? )

						mess = "   #{@prefix}\n   #{(@pre_length + length).to_l}"
						DRAWVIEW.draw_textbox(view, [@pos[1].x, @pos[1].y + 24* UI.scale_factor], mess)

						DRAWVIEW.draw_textbox(view, view.screen_coords(p1.to_a.zip(p2.to_a).map{|c| (c[0] + c[1])/2}), length.to_l.to_s, TextAlignCenter, dim_color, dim_back_color)
					end
				end
			end
			def onLButtonUp(flags, x, y, view)
				if( @state == 0 )
					if( @ip1.valid? )
						case flags
						when 0
							@state = 1
							Sketchup::set_status_text "Select second point", SB_PROMPT
						when 8 #ctrl click
						end
					end
				else
					if( @ip2.valid? )
						case flags
						when 8 #ctrl click
						else
							ip = Sketchup::InputPoint.new @ip2.position
							@action.call(self)
							reset(view)
						end
					end
				end
				view.lock_inference
			end
		end

		class ProfileDraw < ObjPath
			attr_accessor :profile
			def initialize(profile, dialog = nil)
				@path = []
				@profile = profile
				@dialog = dialog
			end
			def onCancel(reason, view)
				view.invalidate
				sel = Sketchup.active_model.selection
				VBO::ShapeForge.disable_shapeforge_sel_observer
				sel.clear
				VBO::ShapeForge.enable_shapeforge_sel_observer
				sel.add @gc
			end
			def deactivate(view)
				view.invalidate
				sel = Sketchup.active_model.selection
				VBO::ShapeForge.disable_shapeforge_sel_observer
				sel.clear
				VBO::ShapeForge.enable_shapeforge_sel_observer
				sel.add @gc
			end

			def apply_junction_style
				return unless @gc && @gc.valid?
				js = @profile.junction_style
				return if js.nil? || js == 'continuous'
				Sketchup.active_model.start_operation("ShapeForge - Junction Style", true)
				pm = VBO::ShapeForge::ForgeElement.new(@gc)
				@gc = pm.draw(js)
				Sketchup.active_model.commit_operation
			end

			def update_preview
				# puts @dialog
				if @dialog == VBO::ShapeForge.profile_dialog.dialog
					@profile.preview(@dialog)
				else
					@profile.preview2(@dialog)
				end
			end
			def onKeyUp(key, repeat, flags, view)
				case key
					when 27		#	Escape key
					when 13		#	Enter key
					when 17		#	ctrl key
						@profile.mirror = !@profile.mirror
						update_preview
						return true
					when 8		#	Backspace key

					when 38		#	Up key
					when 40		#	Down key

					when 37		#	Left key
					when 39		#	Right key

					when 36		#	Home key
						@profile.placement_point = @profile.placement_point + 1
						@profile.placement_point = 1 if @profile.placement_point == 10
						update_preview
						return true
					when 35		#	End key
						@profile.rotation = (@profile.rotation + 90.0) % 360.0
						update_preview
						return true
					else
				end
				nil
			end
			def create_geometry(entities = Sketchup.active_model.active_entities)
				unless @path.empty?
					@gc.erase! if @gc && !@gc.to_s.include?('Delete')

					prof = VBO::ShapeForge::ForgeElement.add(entities, @path)
					@gc = prof.set_from_profile!(@profile)

				end
			end
			def draw(view)

				if @last_point.distance(@path[-1]) > 0
					view.set_color_from_line(@path[-1], @last_point)
					VBO::ShapeForge::DRAWVIEW.draw_path3d(view, @path + [@last_point])
					@profile = VBO::ShapeForge::Shape.new(@profile) if @profile.is_a?(String)

					member = VBO::ShapeForge::Extruder.new(@path + [@last_point], @profile)
					view.line_stipple = ''
					member.draw_view(0, -1, view)
				end
			end
		end

		class AssDraw < ObjPath
			attr_accessor :ass
			def initialize(ass)
				@path = []
				@ass = ass
				@ass.fence.posts.each{|post| post.build_cache}
			end
			def onKeyUp(key, repeat, flags, view)
			end

			def create_geometry(entities = Sketchup.active_model.active_entities)
				unless @path.empty?
					@gc.erase! if @gc && !@gc.to_s.include?('Delete')

					as = VBO::ShapeForge::ForgeStructure.add(entities)
					as.fence = @ass.fence
					as.set_chain @path
					@gc = as.draw
					# sel = Sketchup.active_model.selection
					# sel.clear
					# sel.add @gc
				end
			end
			def get_color_from_line()
				vec = @path[-1].vector_to(@last_point)
				if vec.parallel?(Z_AXIS)
					Sketchup::Color.new('blue')
				elsif vec.parallel?(X_AXIS)
					Sketchup::Color.new('red')
				elsif vec.parallel?(Y_AXIS)
					Sketchup::Color.new('green')
				else
					Sketchup::Color.new('black')
				end
			end

			def draw(view)
				if (view.screen_coords(@path[-1]) - view.screen_coords(@last_point)).length > 10 * UI.scale_factor
					color = get_color_from_line
					view.drawing_color = color
					VBO::ShapeForge::DRAWVIEW.draw_path3d(view, @path + [@last_point])
					ass.fence.rails.each{|rail|
						rail.profile = VBO::ShapeForge::Shape.new(rail.profile) if rail.profile.is_a?(String)
						member = VBO::ShapeForge::Extruder.new(rail.offset_chain(Chain.new(@path + [@last_point]), rail.use_global_up_offset), rail.profile)
						member.draw_view(0, -1, view)
					}
					as = VBO::ShapeForge::ForgeStructure.add(Sketchup.active_model.active_entities)
					as.fence = @ass.fence
					# as.set_chain(@path + [@last_point])
					ass.fence.calc_posts_layout([@path[-1], @last_point])
					color.alpha = 0.5
					view.drawing_color = color
					as.fence.posts.map{|post|
						post.draw(view)
					}
					# as.fence.spans.each{|span|
					# 	span.draw(view)
					# }
				end
			end
		end

		class Pins
			attr_accessor :parent, :indices
			def initialize(parent, indices)
				@indices = indices
				@parent = parent[0]
				@transformation = Sketchup::InstancePath.new(parent[1]).transformation
			end
			def add(index)
				@indices << index unless @indices.include?(index)
			end
			def path
				if @parent.is_a?(VBO::ShapeForge::ForgeElement)
					@parent.chain
				else
					@parent.chain.path
				end
			end
			def transform(tr)
				pa = path.map{|v|
					if @indices.include?(v)
						v.transform(tr)
					else
						v
					end
				}
				@parent.set_chain(pa)
				@parent.draw
			end
		end

		class WrenchTool
			attr_accessor :members, :assemblies, :points, :selected_points, :pts
			def initialize
				@sel = Sketchup.active_model.selection.to_a
				Sketchup.active_model.selection.clear
				@sel = Sketchup.active_model.active_entities if @sel.empty?
				@extend = false
				init_mem_ass
				update_points
			end

			def init_mem_ass
				h = scan(@sel)
				@assemblies = h["assemblies"]
				@members = h["members"]

				@members = @members.to_a.map{|m|
					[
						VBO::ShapeForge::ForgeElement.new(m[-1]),
						m
					]
				}.reject{|a| a[0].nil?}
				@assemblies = @assemblies.to_a.map{|a|
					[
						VBO::ShapeForge::ForgeStructure.read(a[-1]),
						a
					]
				}.reject{|a| a[0].nil?}
			end

			def activate
				@edit_transform = axes_edit_transform
				reset("Hovering")
			end

			def update_points
				@points = []
				@points += @members.map{|m|
					m[0].chain.path.each_with_index.map{|v, i|
						[
							v,
							m,
							i
						]
						}
					}.flatten(1) unless @members.empty?
				@points += @assemblies.map{|m|
					m[0].chain.each_with_index.map{|v, i|
						[
							v,
							m,
							i
						]
					}
				}.flatten(1) unless @assemblies.empty?
				Sketchup.active_model.tools.pop_tool if @points.empty?
			end

			def hovered(flags, x, y, view)
				@points.to_a.find{|p|
					view.screen_coords(p[0].transform(Sketchup::InstancePath.new(p[1][1]).transformation)).distance([x,y]) < 15 * UI.scale_factor
				}
			end

			def get_snap_point(view)
				if @pos
					@points.map{|p| p[0].transform(Sketchup::InstancePath.new(p[1][1]).transformation)}.find{|sn|
						[@pos[1].x, @pos[1].y, 0].distance(view.screen_coords(sn)) < 10 * UI.scale_factor
					}
				end
			end

			def onMouseMove(flags, x, y, view)
				@pos = [flags,[x,y]]
				ph = view.pick_helper
				ph.do_pick(x, y)
				@path = ph.path_at(0)
				@ip = view.inputpoint x,y
				if @path.nil?
					edge = @ip.edge
					face = @ip.face
					@path =  @ip.instance_path.to_a if edge
					@path =  @ip.instance_path.to_a if face
					if @path
						if @path[-1].is_a?(Sketchup::Vertex)
							@path[-1] = @path[-1].edges[0]
						end
					else
					end
				end

				case @state
				when "Hovering"
					hovered(flags, x, y, view)
				when "Dragging Rectangle"
					@pts[1] = view.screen_coords(@ip.position)
				when "Vectoring 1"
					@ip.pick view, x, y

					p_snap = get_snap_point(view)

					if( @ip != @ip1 )
						view.tooltip = p_snap ? "Snap" : @ip.tooltip
						view.invalidate if( @ip.display? or @ip1.display? )

						@ip1.copy! (p_snap ? Sketchup::InputPoint.new(p_snap) : @ip)
					end
				when "Vectoring 2"
					@ip.pick view, x, y, @ip1
					p_snap = get_snap_point(view)
					Sketchup::set_status_text "Length", SB_VCB_LABEL
					if @extend
						@p_shift = calculate_extend()
					end
					if view.inference_locked? || @extend
						p2 = p_snap ? p_snap : @ip.position
						p2_line = p2.project_to_line([@pts[0], @p_shift])
						@ip2.copy!(p2_line ? Sketchup::InputPoint.new(p2_line) : @ip)
					else
						@ip2.copy! (p_snap ? Sketchup::InputPoint.new(p_snap) : @ip)
					end
					view.tooltip = p_snap ? "Snap" : @ip.valid? ? @ip.tooltip : ""
					if( @ip2.valid? )
						length = @ip1.position.distance(@ip2.position)
						Sketchup::set_status_text length, SB_VCB_VALUE
						@pts[1] = @ip2.position
					end
				else
				end
				view.invalidate
			end

			def reset(state, view = nil)
				case state
				when "Hovering"
					@ip = Sketchup::InputPoint.new
					@ip1 = Sketchup::InputPoint.new
					@ip2 = Sketchup::InputPoint.new
					@state = "Hovering"
					@hovered = nil
					@pts = []
					update_points
					@selected_points = []
				when "Vectoring 1"
					@state = "Vectoring 1"
					@pts = []
					@drawn = false
					Sketchup::set_status_text("Select first point.", SB_PROMPT)
					@ip.clear
					@ip1.clear
					@ip2.clear
					@ip_lock=nil
					@ctrl = false
					if( view )
						view.tooltip = nil
						view.invalidate if @drawn
					end
					@edit_transform = axes_edit_transform
				end
			end

			def onCancel(reason, view)
				case reason
				when 0 # ESC
					case @state
					when "Vectoring 1", "Dragging Rectangle"
						reset("Hovering")
					when "Vectoring 2"
						reset("Vectoring 1")
					end
				when 2 # MMB
					init_mem_ass
					update_points
					reset("Hovering")
				end
			end

			def calculate_extend
				tr = Sketchup::InstancePath.new(@hover[1][1]).transformation
				path = @hover[1][0].is_a?(VBO::ShapeForge::ForgeStructure) ? @hover[1][0].chain.map{|c| c.transform(tr) } : @hover[1][0].chain.path.map{|c| c.transform(tr)}
				index = path.index(@ip1.position)
				case index
				when 0
					path[1].vector_to(path[0])
				when path.length - 1
					path[-2].vector_to(path[-1])
				else
					@extend = false
					@ip1.position.vector_to(@ip.position)
				end
			end

			def draw(view)
				Sketchup.set_status_text("#{
					case @state
					when "Hovering"
						"Click or drag to select"
					when "Dragging Rectangle"
						"Click or drag to select"
					when "Vectoring 1"
						"Select first point"
					when "Vectoring 2"
						@hover ? "Select second point of the moving or enter a distance. Tab -> Toggle extend mode" : "Select second point of the moving or enter a distance"
					end
				}")
				color = VBO::ShapeForge::COLOR_MEM_ASS_PATH
				color.alpha = 255
				view.drawing_color = color
				@members.each{|member|
					tr =  Sketchup::InstancePath.new(member[1]).transformation
					puts "PTool draw: drawing member #{member[0].object_id}"
					chain = member[0].chain.path.map{|c| c.transform(tr)}
					puts "  -> chain length: #{chain.length}, first point: #{chain.first}, z in screen: #{view.screen_coords(chain.first).z}"
					VBO::ShapeForge::DRAWVIEW.draw_path3d(
						view,
						chain,
						color
					)
				}
				@assemblies.each{|ass|
					tr =  Sketchup::InstancePath.new(ass[1]).transformation
					puts "PTool draw: drawing assembly #{ass[0].object_id}"
					chain = ass[0].chain.map{|c| c.transform(tr)}
					puts "  -> assembly chain length: #{chain.length}, first z: #{view.screen_coords(chain.first).z}"
					VBO::ShapeForge::DRAWVIEW.draw_path3d(
						view,
						chain,
						color
					)

				}
				view.draw_points(@selected_points.to_a.map{|p| p[0].transform(Sketchup::InstancePath.new(p[1][1]).transformation)}, 12 * UI.scale_factor, 2,VBO::ShapeForge::COLOR_POINT_HOVERED) if @selected_points && !@selected_points.empty?
				p_snap = get_snap_point(view)
				if p_snap
					view.draw_points([p_snap], 15 * UI.scale_factor, 2, VBO::ShapeForge::COLOR_POINT_SNAP)
				end

				case @state
				when "Hovering"
					@hover = @pos.nil? ? nil : hovered(@pos[0], *@pos[1], view)
					if @hover
						tr = Sketchup::InstancePath.new(@hover[1][1]).transformation
						po = @hover[0].transform(tr)
						puts "PTool Hover: drawing point at #{po}"
						view.draw_points([po], 12 * UI.scale_factor, 1, VBO::ShapeForge::COLOR_POINT_HOVERED)

						puts "PTool Hover: calling draw_path3d"
						VBO::ShapeForge::DRAWVIEW.draw_path3d(
							view,
							@hover[1][0].is_a?(VBO::ShapeForge::ForgeStructure) ? @hover[1][0].chain.map{|c| c.transform(tr) } : @hover[1][0].chain.path.map{|c| c.transform(tr)},
							VBO::ShapeForge::COLOR_POINT_HOVERED
						)
						# puts "hovered #{@hover[2]}"
					end
				when "Dragging Rectangle"
					if @pts.length > 1
						rec = rectangle_from_pts
						view.drawing_color = 'black'
						view.line_width = 1
						view.line_stipple = '-'
						view.draw2d(GL_LINE_LOOP, rec)
					end
				when "Vectoring 1"
					p_snap = get_snap_point(view)
					if @ip && @ip.valid? && !p_snap
						@ip.draw(view)
					end
					@drawn = true
				when "Vectoring 2"
					# if @hover
					# 	tr = Sketchup::InstancePath.new(@hover[1][1]).transformation
					# 	po = @hover[0].transform(tr)
					# 	view.draw_points([po], 12 * UI.scale_factor, 1, VBO::ShapeForge::COLOR_POINT_HOVERED)
					# 	path = @hover[1][0].is_a?(VBO::ShapeForge::ForgeStructure) ? @hover[1][0].chain.map{|c| c.transform(tr) } : @hover[1][0].chain.path.map{|c| c.transform(tr)}
					# 	index = path.index(@ip1.position)
					# 	path[index] = @ip.position
					# 	if !@extend
					# 		view.line_stipple = '-'
					# 		view.drawing_color = VBO::ShapeForge::COLOR_POINT_HOVERED
					# 		view.draw2d(GL_LINE_STRIP, path.map{|c| view.screen_coords(c)})
					# 	end
					# end


					if @pts[1] && @pts[0].distance(@pts[1]) > 0
						@drawn = true
						if @p_shift && @ip_lock
							p_snap = get_snap_point(view)
							p = @p_shift
							p = @ip_lock if @ip_lock
							p2 = p_snap ? p_snap : @ip.position
							p2_line = p2.project_to_line([@ip1.position,p])
							view.draw_points p2_line, 7, 2, "red"  if p2_line

							@ip2.copy! Sketchup::InputPoint.new(p2_line)
							view.line_stipple = "__"
							view.drawing_color ="blue"
							view.draw_line(p2, @ip2.position)
							view.line_stipple = ""
							view.drawing_color ="black"
						end

						if (@ip && @ip.valid? && !p_snap)
							@ip.draw(view)
						end
						if @extend
							# puts "ex"
							view.line_width = 3
							DRAWVIEW.draw_path3d(view, @pts, VBO::ShapeForge::COLOR_MEM_ASS_PATH)
						else
							view.set_color_from_line(*@pts)
							view.line_width = view.inference_locked? ? 3 : 1
							DRAWVIEW.draw_path3d(view, @pts)
							# view.draw(GL_LINE_STRIP, @pts)
						end
						cal_stretch.each{|path|
							view.line_stipple = ''
							view.drawing_color = VBO::ShapeForge::COLOR_POINT_HOVERED
							view.draw(GL_LINE_STRIP, path)
						}
					end
				else
				end
			end

			#------------------------onLButton--------------------------------------
			def onLButtonDown(flags, x, y, view)
				case @state
				when "Hovering"
					hover = hovered(flags, x, y, view)
					if hover
						@selected_points = [hover]
						p_snap = hover[0].transform(Sketchup::InstancePath.new(hover[1][1]).transformation)
						@pts[0] = p_snap
						@ip1 = Sketchup::InputPoint.new(p_snap)

						@state = "Vectoring 1"
					else
						@pts[0] = view.screen_coords(@ip.position)
						@state = "Dragging Rectangle"
					end

				else
				end
			end

			def onLButtonUp(flags, x, y, view)
				case @state
				when "Dragging Rectangle"
					@pts[-1] = view.screen_coords(@ip.position)
					if @pts[0].distance(@pts[1]) > 10 * UI.scale_factor
						get_selected_points(view)
						@pts = []
						@state = "Vectoring 1"
						view.lock_inference if view.inference_locked?
						view.invalidate
					else
						@pts = []
						@state = "Hovering"
						view.invalidate
					end
				when "Vectoring 1"
					@extend = false
					@hover = @pos.nil? ? nil : hovered(@pos[0], *@pos[1], view)
					p_snap = get_snap_point(view)
					@pts[0] = p_snap ?  p_snap : @ip.position
					view.lock_inference if view.inference_locked?
					@state = "Vectoring 2"
				when "Vectoring 2"
					p_snap = get_snap_point(view)
					if @extend
						@p_shift = calculate_extend()
					end
					if view.inference_locked? || @extend
						p = @p_shift
						p = @ip_lock if @ip_lock
						p2 = p_snap ? p_snap : @ip.position
						p2_line = p2.project_to_line([@ip1.position,p])
						@pts[1] = p2_line
					else
						@pts[1] = p_snap ?  p_snap : @ip.position
					end
					do_stretch
					reset("Hovering")
				end
			end

			def onUserText(text, view)
				if @state == "Vectoring 2"
					return if not @ip2.valid?
					if text.start_with?('=')
					else
						begin
							value = text.to_l.to_f
							Sketchup::set_status_text value, SB_VCB_VALUE
							pt1 = @ip1.position
							vec = pt1.vector_to(@ip2.position)
							if( vec.length == 0.0 )
								UI.beep
								return
							end
							vec.length = value
							pt2 = pt1 + vec
							@ip2.copy! Sketchup::InputPoint.new(pt2)
							@pts = [pt1, pt2]
							do_stretch
							reset("Hovering")
						rescue => e
							UI.messagebox(e)
						end
					end
				elsif @state == 0
				end
			end

			#--------Keyboard Events--------------------------------

			def onKeyDown(key, repeat, flags, view)
				p_snap = get_snap_point(view)
				if( key == CONSTRAIN_MODIFIER_KEY )
					@shift_down_time  = true
					view.lock_inference if view.inference_locked?
					if @state == "Vectoring 1" && @ip1.valid?
						view.lock_inference @ip1
					elsif @state == "Vectoring 2" && @ip.valid?
						@p_shift = @pts[0].vector_to(@ip.position)
						p2 = p_snap ? p_snap : @ip.position
						p2_line = p2.project_to_line([@ip1.position,@p_shift])
						view.lock_inference(
							Sketchup::InputPoint.new(p2_line),
							@ip1
						)
					end
				end
			end
			def onKeyUp(key, repeat, flags, view)
				case key
					when 27		#	Escape key
					when 13		#	Enter key
					when CONSTRAIN_MODIFIER_KEY 		#	Shift key
						@shift_down_time=nil
						@p_shift=nil
						view.lock_inference
						view.invalidate
					when COPY_MODIFIER_KEY 		#	Alt/Option on Mac, Ctrl on PC
					when ALT_MODIFIER_KEY 		#	Command on Mac, Alt on PC

					when 9		#	Tab key
						if @state == "Vectoring 2" && @hover
							@extend = !@extend
						else
							@extend = false
						end
					when 8		#	Backspace key

					when 38, 40	#	Up key
						if @ip.valid? && @state == "Vectoring 2"
							@p_shift = Z_AXIS
							p2_line =  @ip.position.project_to_line([@ip1.position,@p_shift])
							view.lock_inference(
								Sketchup::InputPoint.new(p2_line),
								@ip1
							)
							onMouseMove(@pos[0], *@pos[1], view)
						end

					when 37		#	Left key
						if @ip.valid? && @state == "Vectoring 2"
							@p_shift = Y_AXIS
							p2_line =  @ip.position.project_to_line([@ip1.position,@p_shift])
							view.lock_inference(
								Sketchup::InputPoint.new(p2_line),
								@ip1
							)
							onMouseMove(@pos[0], *@pos[1], view)
						end
					when 39		#	Right key
						if @ip.valid? && @state == "Vectoring 2"
							@p_shift = X_AXIS
							p2_line =  @ip.position.project_to_line([@ip1.position,@p_shift])
							view.lock_inference(
								Sketchup::InputPoint.new(p2_line),
								@ip1
							)
							onMouseMove(@pos[0], *@pos[1], view)
						end

					when 36		#	Home key
					when 35		#	End key
					else
				end

			end



			private
			def cal_stretch
				vector = @pts[1] - @pts[0]
				act = @selected_points.group_by{|c| c[1]}
				paths = []
				act.each{|m, points|
					tr = Sketchup::InstancePath.new(m[1]).transformation
					ch = m[0].is_a?(VBO::ShapeForge::ForgeStructure) ? m[0].chain.map{|c| c.transform(tr)} : m[0].chain.path.map{|c| c.transform(tr)}
					# ch = m[0].chain.path.map{|c| c.transform(tr)}
					points.each{|point|
						i = point[2]
						trans = Geom::Transformation.translation(vector)
						new_point = ch[i].transform(trans)
						if m[0].is_a?(VBO::ShapeForge::ForgeElement)
							if i == 0
								cap = m[0].get_attribute("cap_0_trim")
								m[0].set_attribute("cap_0_trim", nil) if cap && cap[0] == "plane" && !new_point.on_plane?(cap[2])
							end
							if i == ch.length - 1
								cap = m[0].get_attribute("cap_1_trim")
								m[0].set_attribute("cap_1_trim", nil) if cap && cap[0] == "plane" && !new_point.on_plane?(cap[2])
							end
						end
						ch[i] = new_point
					}
					paths << ch
				}
				paths
			end
			def do_stretch
				vector = @pts[1] - @pts[0]
				Sketchup.active_model.start_operation("Stretch", true)
				act = @selected_points.group_by{|c| c[1]}
				act.each{|m, points|
					ch = m[0].is_a?(VBO::ShapeForge::ForgeStructure) ? m[0].chain : m[0].chain.path
					# ch = m[0].chain.path
					if points.length == ch.length
						trans = Geom::Transformation.translation(vector)
						m[0].group.transform!(trans)
					else
						points.each{|point|
							i = point[2]
							tr = Sketchup::InstancePath.new(m[1]).transformation.inverse
							trans = Geom::Transformation.translation(vector.transform(tr))
							new_point = ch[i].transform(trans)
							if m[0].is_a?(VBO::ShapeForge::ForgeElement)
								if i == 0
									cap = m[0].get_attribute("cap_0_trim")
									m[0].set_attribute("cap_0_trim", nil) if cap && cap[0] == "plane" && !new_point.on_plane?(cap[2])
								end
								if i == ch.length - 1
									cap = m[0].get_attribute("cap_1_trim")
									m[0].set_attribute("cap_1_trim", nil) if cap && cap[0] == "plane" && !new_point.on_plane?(cap[2])
								end
							end
							ch[i] = new_point
						}
						if m[0].group.definition.instances.length > 1
							m[0].group = m[0].group.make_unique
							m[0].instance_variable_set(:@su_defn, m[0].group.definition)
						end

						m[0].set_chain(ch)
						m[1].find_all{|c| c.is_a?(Sketchup::Group)}.each{|c|
							c.make_unique
						}
						m[0].draw
						if m[0].is_a?(VBO::ShapeForge::ForgeElement)
							m[0].re_coordinate(m[0].transformation)
						end
					end
				}
				Sketchup.active_model.commit_operation
			end

			def axes_edit_transform
				model=Sketchup.active_model
				return model.axes.transformation if Sketchup.version.to_i>=16
				model.start_operation "get edit transform", true
				ents = model.active_entities
				begin
					g = ents.add_group(ents.add_group)
					t = Geom::Transformation.new(g.transformation.xaxis,g.transformation.yaxis,g.transformation.zaxis,g.transformation.origin)
					g.erase! if g && g.valid? && !g.deleted?
				rescue
					t = model.edit_transform
				end
				model.abort_operation
				return t
			end
			def rectangle_from_pts
				p1,p2 = @pts
				[
					Geom::Point3d.new(p1.x, p1.y, 0),
					Geom::Point3d.new(p2.x, p1.y, 0),
					Geom::Point3d.new(p2.x, p2.y, 0),
					Geom::Point3d.new(p1.x, p2.y, 0),
				]
			end

			def point_inside_rectangle?(point)
				p1,p2 = @pts
				point.x > p1.x && point.x < p2.x && point.y > p1.y && point.y < p2.y
			end

			def get_selected_points(view)
				@selected_points = @points.select{|p|
					point_inside_rectangle?(view.screen_coords(p[0].transform(Sketchup::InstancePath.new(p[1][1]).transformation)))
				}

			end

			def scan(ents, path = [])
			classes = [classes] unless classes.is_a?(Array)
			list = {}
			ents.each{|e|
				if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
					member = VBO::ShapeForge::Identify.profile_member?(e)
					ass = VBO::ShapeForge::Identify.assembly?(e)
					if member
						if list["members"].nil?
							list["members"] = [path + [e]]
						else
							list["members"] << path + [e]
						end
					elsif ass
						if list["assemblies"].nil?
							list["assemblies"] = [path + [e]]
						else
							list["assemblies"] << path + [e]
						end
					else
						list = list.merge(scan(e.definition.entities, path + [e])){|key, old_val, new_val|
							(old_val + new_val).uniq
						}
					end
				end
			}
			list
			end
		end

		class ObjectToForgeTool
			include Geometry

			def initialize(entities)
				@entities = entities
				@current_entity = entities.first
				@highlight_face = nil
				@highlight_color = Sketchup::Color.new(255, 100, 0, 80)
				@edge_color = Sketchup::Color.new(255, 100, 0, 255)
			end

			def activate
				Sketchup.status_text = "Click a face to use as the cross-section profile. Press Esc to cancel."
				Sketchup.active_model.active_view.invalidate
			end

			def deactivate(view)
				view.invalidate
			end

			def onMouseMove(flags, x, y, view)
				ph = view.pick_helper
				ph.do_pick(x, y)
				best = ph.best_picked

				if best.is_a?(Sketchup::Face)
					path = ph.path_at(0)
					# Check if the face belongs to one of our target entities
					if path && path.to_a.any? { |p| @entities.include?(p) }
						@highlight_face = best
						@pick_path = path
						@pick_transformation = Sketchup::InstancePath.new(path).transformation
					else
						@highlight_face = nil
						@pick_path = nil
					end
				else
					@highlight_face = nil
					@pick_path = nil
				end
				view.invalidate
			end

			def onLButtonDown(flags, x, y, view)
				return unless @highlight_face && @pick_path

				# Find which target entity this face belongs to
				entity = @pick_path.to_a.find { |p| @entities.include?(p) }
				return unless entity

				trans = entity.transformation
				face = @highlight_face

				# Create profile from selected face
				profile = VBO::ShapeForge::Shape.new(face)

				# Set name from entity name
				entity_name = entity.name.to_s.strip
				if entity_name.empty? && entity.respond_to?(:definition)
					entity_name = entity.definition.name.to_s.strip
				end
				entity_name = "Shape Forge" if entity_name.empty?
				profile.name = entity_name

				# Compute path: trace perpendicular edges from the face
				face_vertices = face.vertices
				profile_edges_set = Set.new(face.edges)

				# Find the opposite end by tracing longitudinal edges
				longitudinal_chains = []
				face_vertices.each do |sv|
					chain_pts = [sv.position.transform(trans)]
					current_vertex = sv
					visited = Set.new([current_vertex])

					100.times do
						next_edge = current_vertex.edges.find { |e|
							!profile_edges_set.include?(e) &&
							!visited.include?(e.other_vertex(current_vertex))
						}
						break unless next_edge

						next_vertex = next_edge.other_vertex(current_vertex)
						chain_pts << next_vertex.position.transform(trans)
						visited << next_vertex
						current_dir = current_vertex.position.vector_to(next_vertex.position)
						current_vertex = next_vertex

						# Continue tracing
						candidate_edges = current_vertex.edges.select { |e|
							other = e.other_vertex(current_vertex)
							!visited.include?(other) && !profile_edges_set.include?(e)
						}

						if candidate_edges.length > 1
							best_edge = candidate_edges.min_by { |e|
								dir = current_vertex.position.vector_to(e.other_vertex(current_vertex).position)
								dir.valid? && current_dir.valid? ? current_dir.angle_between(dir) : Float::INFINITY
							}
							next_edge = best_edge
						elsif candidate_edges.length == 1
							next_edge = candidate_edges[0]
						else
							break
						end

						next_vertex = next_edge.other_vertex(current_vertex)
						chain_pts << next_vertex.position.transform(trans)
						visited << next_vertex
						current_vertex = next_vertex
					end

					longitudinal_chains << chain_pts if chain_pts.length >= 2
				end

				# Build chain from longitudinal midpoints
				if longitudinal_chains.empty?
					# Fallback: use face normal direction with bounding box depth
					center = Geom::Point3d.new(face.bounds.center).transform(trans)
					normal = face.normal.transform(trans)
					bb = entity.definition.bounds
					depth = [bb.width, bb.height, bb.depth].max
					chain_points = [center, center.offset(normal, depth)]
				else
					max_len = longitudinal_chains.max_by(&:length).length
					chain_points = []
					max_len.times do |i|
						pts = longitudinal_chains.map { |lc| lc[i] }.compact
						next if pts.empty?
						avg = pts.reduce([0,0,0]) { |sum, pt|
							[sum[0] + pt.x, sum[1] + pt.y, sum[2] + pt.z]
						}
						chain_points << Geom::Point3d.new(avg[0] / pts.length, avg[1] / pts.length, avg[2] / pts.length)
					end
					if chain_points.length < 2
						center = Geom::Point3d.new(face.bounds.center).transform(trans)
						normal = face.normal.transform(trans)
						bb = entity.definition.bounds
						depth = [bb.width, bb.height, bb.depth].max
						chain_points = [center, center.offset(normal, depth)]
					end
				end

				# Create ForgeElement
				model = Sketchup.active_model
				model.start_operation("Object to Shape Forge (Manual)", true)
				begin
					parent_ents = entity.parent.entities
					pm = VBO::ShapeForge::ForgeElement.add(parent_ents, chain_points)
					if pm
						pm.set_from_profile!(profile)
						@entities.delete(entity)
						entity.erase!
					end
					model.commit_operation
				rescue => e
					model.abort_operation
					puts "Object to Shape Forge (Manual) error: #{e.message}"
					puts e.backtrace.first(5).join("\n")
				end

				# Continue with remaining entities or finish
				if @entities.empty?
					Sketchup.active_model.tools.pop_tool
				else
					@current_entity = @entities.first
					Sketchup.status_text = "Click a face to use as the cross-section profile. #{@entities.length} object(s) remaining. Press Esc to cancel."
					view.invalidate
				end
			end

			def draw(view)
				return unless @highlight_face && @highlight_face.valid? && @pick_transformation

				# Draw highlighted face outline
				verts = @highlight_face.outer_loop.vertices
				pts = verts.map { |v| v.position.transform(@pick_transformation) }

				view.drawing_color = @edge_color
				view.line_width = 3
				view.draw(GL_LINE_LOOP, pts)

				view.drawing_color = @highlight_color
				view.draw(GL_POLYGON, pts)
			end

			def onCancel(reason, view)
				Sketchup.active_model.tools.pop_tool
			end

			def getExtents
				bb = Geom::BoundingBox.new
				@entities.each { |e| bb.add(e.bounds) if e.valid? }
				bb
			end
		end

	end
end
