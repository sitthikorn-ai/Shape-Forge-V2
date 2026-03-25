
require 'sketchup.rb'
Sketchup.require File.join(File.dirname(__FILE__), 'member')
Sketchup.require File.join(File.dirname(__FILE__), 'tools')
Sketchup.require File.join(File.dirname(__FILE__), 'drawview')
module VBO
	module ShapeForge
		def self.camel_to_snake(str)
			('@' + str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
					gsub(/([a-z\d])([A-Z])/, '\1_\2').
					downcase.gsub('_guid','GUID').gsub('-','_')).to_sym
		end
		def self.snake_to_camel(str,space='')
			str.to_s.delete('@').split('_').map(&:capitalize).join(space).gsub('guid','GUID').gsub('AutoTrim','Auto-Trim')
		end
		def self.correct_filename(filename)
			corrected_filename = filename.gsub(/\s+/, '')
															.gsub('*_*', '_').gsub("%20", "_")
															.gsub('~', '')
															.gsub('-', '_')
                             .gsub(/^_|_$/, '')
                             .gsub(/(\d+)\s+(\d+)\/(\d+)/) { "#{$1}_#{($2.to_i / $3.to_f).round(4)}" }
			# puts corrected_filename
			corrected_filename.gsub(/_+/, '_')
		end

		def self.send_to_overlay(shape)
			ov = Sketchup.active_model.overlays.find{|c| c.overlay_id == "shapeforge_overlay"}
			if ov
				ov.shape = shape
				# ov.enabled = true
				# Sketchup.active_model.active_view.invalidate
			end
		end

		module Geometry
			def middle_point(p1,p2)
				p1.to_a.zip(p2.to_a).map{|c| (c[0] + c[1])/2}
			end

			def center(p1,p2,p3)
				plane = Geom.fit_plane_to_points(p1,p2,p3)
				line1 = Geom.intersect_plane_plane(
					[
						middle_point(p1,p2),
						p1.vector_to(p2)
					],
					plane
				)
				line2 = Geom.intersect_plane_plane(
					[
						middle_point(p1,p3),
						p1.vector_to(p3)
					],
					plane
				)
				if line1 && line2
					Geom.intersect_line_line(line1, line2)
				end
			end

			def clock_wise_angle(v1, v2, normal = Z_AXIS)
				angle = v1.angle_between(v2)
				cross_product = v1 * v2
				angle = 2 * Math::PI - angle if cross_product % normal < 0
				angle
			end

			def arc(p1,p2,p3,segments)
				center = center(p1,p2,p3)
				if center
					radius = center.vector_to(p1).length
					plane = Geom.fit_plane_to_points(p1,p2,p3)
					normal = plane[0..2]
					v1, v2 = [p1, p2].map{|c| center.vector_to(c)}
					total_angle = clock_wise_angle(v1,v2, normal)
					if total_angle > Math::PI
						total_angle = Math::PI * 2 - total_angle
						p1,p2 = p2,p1
					end
					seg_angle = total_angle / segments
					arc_pol = [p1]
					rot = Geom::Transformation.rotation(center, normal, seg_angle)
					segments.times{|i|
						arc_pol << arc_pol[-1].transform(rot)
					}
					arc_pol
				else
					[p1, p2]
				end
			end

			def point_on_plane?(plane,p)
				value=plane[0]*p.x+plane[1]*p.y+plane[2]*p.z+plane[3]
				return value
			end

			def thru_face(line, face, trans)
				plane = [face.vertices[0].position, face.normal].map{|c| c.transform(trans)}
				#polygon = face.outer_loop.vertices.map{|c| c.position.transform(trans)}
				intersect = Geom.intersect_line_plane(line, plane)
				return nil if intersect.nil?
				#[16,32].include?(face.classify_point(intersect.transform(trans.inverse))) ? nil : intersect
				[intersect, face.classify_point(intersect.transform(trans.inverse))]
			end

			def translate_to_2d_coordinates(points)
				plane = Geom::fit_plane_to_points(points)
				projected_points = points.map{|pp| pp.project_to_plane(plane)}

				#origin = ORIGIN.project_to_plane(plane)
				# plane_normal = origin.vector_to(ORIGIN)
				plane_normal = Geom::Vector3d.new(plane[0..2])
				if plane_normal.length != 0
					axes = plane_normal.axes
					trans = Geom::Transformation.axes(points[0], axes[0], axes[1], axes[2]).inverse
				else
					trans = Geom::Transformation.new(points[0])
				end
				t_points = projected_points.map{|c| c.transform(trans)}
			end

			def get_rotate_angle(p1, p2)
				p01, p02 = [p1, p2].map{|c| translate_to_2d_coordinates(c)}
				# tr = Geom::Transformation.translation(p01[0].vector_to(p02[0]))
				# p01.map!{|c| c.transform(tr)}
				# g = Sketchup.active_model.entities.add_group
				# g.entities.add_face(p01)
				# g.entities.add_face(p02)
				# Sketchup.active_model.selection.clear
				# Sketchup.active_model.selection.add(g)
				clock_wise_angle(p01[0].vector_to(p01[-1]), p02[0].vector_to(p02[-1])).radians.round(2) % 360
				# p01[0].vector_to(p01[1]).angle_between(p02[0].vector_to(p02[1])).radians.round(2) % 360
			end

			def get_ray_max_distance(ray)
				ray = ray.sort_by{|c| c[2]}
				found = ray.find{|c| c[1] == Sketchup::Face::PointInside}
				found = ray.first if found.nil?
				found
			end

			def get_inst_below_cursor(view,x,y,active=true)
				pickray=view.pickray(x,y)
				model=view.model
				rt=model.raytest(pickray)
				active_ents=Sketchup.active_model.active_entities
				if rt
					path=rt[1]
					ent=path[-2]
					if (ent.class==Sketchup::Group or ent.class==Sketchup::ComponentInstance)
						if ((active) and (active_ents.include?(ent)))
							return ent
						elsif (!active)
							return ent
						end
					end
				end
				return nil
			end

			def get_trans_below_cursor(view,x,y,active=true)
				pickray=view.pickray(x,y)
				model=view.model
				rt=model.raytest(pickray)
				trans=Geom::Transformation.new

				if rt
					path=rt[1]
					ent=path.pop()
					path.each {|inst| trans=trans*inst.transformation}
				end
				return trans
			end

			def draw_picked_face(view,face,trans, polyline=false)
				if face
					if face.class==Sketchup::Face
						return if !face.valid?
						verts=face.outer_loop.vertices
					elsif face.class==Array
						verts=face
					else
						raise ArgumentError,"Face or Array expected",caller
					end
					view.drawing_color=@highlight_color
					view.line_width = 24
					view.line_stipple=""
					pts=verts.collect {|v| v.position.transform(trans) if v.valid?}
					view.draw(GL_LINE_LOOP,pts) if !polyline
					view.draw(GL_LINE_STRIP,pts) if polyline
				end
			end

			def point_on_edge1(pt,edge)
				dist=nil

				p0=edge[0]
				p1=edge[1]

				dist=0.0 if pt==p0
				edge_vec=p0.vector_to(p1)
				edge_vec_length=edge_vec.length
				dist=edge_vec_length if pt==p1

				if !dist
					start_to_pt=p0.vector_to(pt).length
					pt_to_end=pt.vector_to(p1).length
					if (start_to_pt+pt_to_end)==edge_vec_length
						dist=start_to_pt
					else
						dist=nil
					end
				end
				return dist
			end

			def point_on_edge(pt,edge)
				pt1, pt2 = edge
				x1, y1, z1 = pt1.to_a
				x2, y2, z2 = pt2.to_a
				x, y, z = pt.to_a
				(x1-x2)*(x1-x2) + (y1-y2)*(y1-y2) + (z1-z2)*(z1-z2) >= (x1-x)*(x1-x) + (y1-y)*(y1-y) + (z1-z)*(z1-z) + (x2-x)*(x2-x) + (y2-y)*(y2-y) + (z2-z)*(z2-z)
			end
			def get_max_perp_edge_length(verts)

				range=get_range_perpindicular_edge_length(verts)
				return range[1]

			end

			def get_min_perp_edge_length(verts)

				range=get_range_perpindicular_edge_length(verts)
				return range[0]

			end

			def get_range_perpindicular_edge_length(verts)

				perp_edges=get_perpindicular_edges(verts)
				perp_edges_lengths=perp_edges.collect {|pe| pe.length.to_f}
				return [perp_edges_lengths.min,perp_edges_lengths.max]

			end

			def get_perpindicular_edges(verts)

				perp_edges=[]

				adj_edges=verts.collect {|v| v.edges}
				adj_edges.flatten!

				adj_edges.delete_if {|edge| verts.include?(edge.start)&&verts.include?(edge.end)}

				return adj_edges

			end

			def get_perpindicular_edges_old(verts)

				perp_edges=[]
				normal = get_normal_of_vertices(verts)

				verts.each {|v|
					edges=v.edges
					perp_edge=edges.find {|edge| edge.line[1].parallel?(normal)}
					perp_edges.push(perp_edge)
				}

				return perp_edges

			end

			def get_max_distance_to_plane(verts, plane, trans)

				vectors=[]
				normal = get_normal_of_vertices(verts).transform(trans)

				verts.each {|v|
					p1=v.position.transform(trans)
					line=[p1,normal]
					p2=Geom.intersect_line_plane(line,plane)
					if p2.nil?
						return nil  #does not intersect
					end
					vectors.push(p1.vector_to(p2))
				}

				vector_lengths=vectors.collect {|vec| vec.length}
				max_length=vector_lengths.max

				if max_length==0.0
					return max_length
				end

				vec_index=vector_lengths.index(max_length)
				max_vector=vectors[vec_index]

				if !max_vector.samedirection?(normal)
					max_length=-(max_length)
				end

				return max_length

			end

			def nudge_ray(ray)

				nudge_dist=0.01
				vec=ray[1]
				pt=ray[0]
				vec.length=nudge_dist
				pt=pt.offset(vec)
				return [pt,ray[1]]

			end

			def divide_edge(edge)

				p0=edge[0]
				p1=edge[1]
				new_pts=[]
				vec=p0.vector_to(p1)
				v_len=vec.length
				p=Geom::Point3d.new(p0)
				new_pts.push(p)
				divs=(v_len/0.1).floor

				if v_len>0.0
					vec.length=(v_len)/(divs.to_f)
					new_pts=[]
					(divs-1).times {|i|
						p=Geom::Point3d.new(p.offset(vec))
						new_pts.push(p)
					}
				else
					new_pts=edge
				end

				new_pts.push(Geom::Point3d.new(p1))

				return new_pts

			end

			def get_max_perp_distance_from_face_to_entity(face, entity, trans)
				#trans = Geom::Transformation.new
				if face
					model = Sketchup.active_model
					face_normal = face.normal.transform(trans)
					face_verts = face.outer_loop.vertices
					face_pts = face_verts.collect {|v| v.position.transform(trans)}
					chain = Chain.new(face_pts)
					chain.add(face_pts[0])  #close the loop of the chain
					edges = chain.edges
					face_pts = edges.collect {|edge| divide_edge(edge)}
					face_pts.flatten!

					face_rays=face_pts.collect {|p| [p,face_normal]}
					face_rays=face_rays.collect {|ray| nudge_ray(ray)}

					hit_entity=[]
					distance_to_entity=[]

					face_rays.each_index {|index|
						item=model.raytest(face_rays[index])
						running_distance=0.0
						current_ray_origin=face_pts[index]

						while item
							path_array = item[1]
							hit_point = item[0]
							running_distance += (current_ray_origin.distance(hit_point))

							if path_array.index(entity)
								hit_entity.push(true)
								item=nil
							else
								current_ray_origin=hit_point
								new_ray=[current_ray_origin,face_normal]
								item=model.raytest(new_ray)
							end

						end

						if running_distance == 0.0
							hit_entity.push(false)
						end
						distance_to_entity.push(running_distance)
					}

					if hit_entity.index(true)
						return distance_to_entity.max.to_f + 0.1
					else
						return nil
					end
				else
					return nil
				end

			end

			def get_closest_face_to_point(faces, point)
				#return if faces.any? { |f| !f.is_a?(Sketchup::Face)}
				faces.min_by{|f|
					vectors = f.edges.map{|c| c.line[1]}.combination(2).to_a.find{|c| !c[0].parallel?(c[1])}
					vector = vectors[0] * vectors[1]
					point.distance point.project_to_plane([f.vertices[0].position, vector].map{|c| c.transform(transformation)})
				}
			end

			def polygon_area(pts,transformation=Geom::Transformation.new)

				pts=pts.collect {|p| p.transform(transformation)}  #transform the points
				pts.push(pts.first)  #close the loop

				sum=0.0
				num_points=pts.length
				(num_points-1).times {|i|
					sum+=(pts[i].x*pts[i+1].y)-(pts[i+1].x*pts[i].y)
				}

				return (0.5*sum)

			end

			def get_normal_of_vertices_(verts)
				#UI.messagebox verts.to_s
				return if verts.nil? || verts.empty?
				edges = verts[0].edges
				perp_edge = edges.find {|edge| verts.index(edge.other_vertex(verts[0])).nil?}
				return unless perp_edge
				edge_vector = perp_edge.other_vertex(verts[0]).position.vector_to(verts[0].position)
				return edge_vector.normalize
			end

			def get_normal_of_vertices(verts)
				vset = verts.map{|c| c.position}.combination(3).to_a

				vset_ = vset.find{|c| !c[0].vector_to(c[1]).parallel?(c[0]).vector_to(c[2])}
				UI.messagebox vset_.to_s
				vector = vset_[0].vector_to(vset_[1]) * vset_[0].vector_to(vset_[2])
				vector.normalize
			end

			def transform_by_placement_point(points, placement_point)
				return Geom::Transformation.new if points.nil? || points.empty?
				# puts "transform_by_placement_point: #{points}"
				box=Geom::BoundingBox.new
				box.add(points.to_a)
				min=box.min
				max=box.max
				cent=box.center
				case placement_point

				when 1 #top right
					pp=[min.x,max.y,0.0]
				when 2 #top middle
					pp=[cent.x,max.y,0.0]
				when 3 #top right
					pp=[max.x,max.y,0.0]
				when 4 #mid left
					pp=[min.x,cent.y,0.0]
				when 5 #centroid
					pp=cent
				when 6 #mid right
					pp=[max.x,cent.y,0.0]
				when 7 #bot left
					pp=min
				when 8 #bot middle
					pp=[cent.x,min.y,0.0]
				when 9 #bot right
					pp=[max.x,min.y,0.0]

				end

				trans=Geom::Transformation.new(pp)
				trans.invert!
				trans
			end
			def transform_by_rotation(points,rotation)

				rot_radians=rotation.degrees
				rot_trans=Geom::Transformation.rotation([0,0,0],[0,0,1],rot_radians)
				return rot_trans

			end

			def transform_by_offset(points,x_offset,y_offset)

				offset_trans=Geom::Transformation.translation(Geom::Vector3d.new(x_offset,y_offset,0.0))
				return offset_trans

			end


			def transform_by_size(x_size,y_size,x_scale,y_scale)

				scale_trans=Geom::Transformation.scaling(x_scale,y_scale,1.0)
				return scale_trans

			end

			def transform_by_mirror(points)

				mirror_trans=Geom::Transformation.scaling(-1,1,1)
				return mirror_trans

			end

			def projected_face_area(f,vector)

				f_normal=f.normal
				projected_area=f.area*(f_normal.dot(vector)).abs
				return projected_area

			end

		end
		module Identify
			def self.profile_member?(ent)
				return if ent.nil? || ent.to_s.include?("Delete")
				is_member = ent.respond_to?(:definition) ? ent.definition.get_attribute("ProfileBuilder", "profile") : nil
				is_member.nil? ? nil : ForgeElement.new(ent)
			end

			def self.assembly?(ent)
				return if ent.nil? || ent.to_s.include?("Delete")
				ent.respond_to?(:definition) ? ent.definition.get_attribute("PBFence","is_fence") : nil
			end

			def self.profile_temp?(ent)
				return if ent.nil? || ent.to_s.include?("Delete")
				ent.respond_to?(:definition) ? ent.definition.get_attribute("VBO ShapeForge", "Shape Temporary") : nil
			end
			def self.branch?(ent)
				return if ent.nil? || ent.to_s.include?("Delete")
				is_branch = ent.respond_to?(:definition) ? ent.definition.get_attribute("VBO ShapeForge", "Branch") : nil
				is_branch.nil? ? nil : Branch.new(ent)
			end

		end
		class ProfileMaterial

			def initialize(su_mat)
				if su_mat.kind_of?(String)
					mats=Sketchup.active_model.materials
					if su_mat!="Default"
						su_mat=mats[su_mat]
					else
						su_mat=nil
					end
				end

				if su_mat
					@su_material=su_mat
					@su_color=su_mat.color
					@su_alpha=su_mat.alpha
					@su_name=su_mat.name
					@su_texture=su_mat.texture
					if @su_texture
						@has_texture=true
						@su_texture_filename=@su_texture.filename
						@su_texture_width=@su_texture.width
						@su_texture_height=@su_texture.height
						save_texture_to_temp()
					end
					@su_dicts=su_mat.attribute_dictionaries
					if @su_dicts
						@dicts={}
						@su_dicts.each {|su_dict|
							dict={}
							su_dict.each {|key,val| dict[key]=val}
							@dicts[su_dict.name]=dict
						}
					end
				end

			end

			def save_texture_to_temp()

				if @has_texture
					tw=Sketchup.create_texture_writer
					group=Sketchup.active_model.entities.add_group
					group.material=@su_material
					tw.load(group)
					f_name=File.join(Sketchup.temp_dir,File.basename(@su_texture_filename))
					status=tw.write(group,f_name)
					@su_texture_filename=f_name
				end

			end

			def to_su_material()

				if @su_material
					mats=Sketchup.active_model.materials
					mat=mats[@su_name]
					if mat.nil?
						mat=mats.add(@su_name)
						mat.color=@su_color
						mat.alpha=@su_alpha
						if @has_texture
							mat.texture=@su_texture_filename
							mat.texture.size=[@su_texture_width,@su_texture_height]
						end
						if @dicts
							@dicts.each {|name,dict|
								dict.each {|key,val| mat.set_attribute(name,key,val)}
							}
						end
					end
					mat
				else
					nil
				end
			end
		end

		class Shape
			include Geometry
			attr_accessor :placement_point,:mirror,:rotation,:x_offset,:y_offset,:smooth_angle, :material_name, :layer_name, :version,
			:outer,:junction_style,:extrude_mode
			public
			def initialize(object, name = "")
				name = "Shape%20Forge" if name == ""
				@name = name
				@outer_loop = []
				@holes = []
				@placement_point = 5
				@mirror = false
				@rotation = 0.0
				@x_offset = 0.0
				@y_offset = 0.0
				@smooth_angle = 45.0
				@file_path = nil
				@dimension = 2
				@material_name = "Default"
				@layer_name = Sketchup.active_model.layers[0].name
				@dict = "ProfileBuilder"
				@key = "Properties"
				@x_scale = 1.0
				@y_scale = 1.0

				@junction_style = 'continuous'
				@extrude_mode = 'follow_me_mode'
				if object.is_a?(String)
					load_from_string(object)
				elsif object.is_a?(Sketchup::Face) || object.is_a?(Array)
					self.profile = object
				elsif object.is_a?(VBO::ShapeForge::Shape)
					return Shape.new(object.to_s)
				elsif object.respond_to?(:definition)
					load_from_defn(object.definition)
				end
				# reduce_profile
			end

			def x_scale=(value)
				@x_scale=value.to_f
			end

			def x_scale
				return @x_scale
			end

			def y_scale=(value)
				@y_scale=value.to_f
			end

			def y_scale
				return @y_scale
			end

			def save_skp(filename)


				cam = Sketchup.active_model.active_view.camera
				eye = cam.eye
				target = cam.target
				up = cam.up

				temp_target = Geom::Point3d.new(0,0,0)
				temp_up = Geom::Vector3d.new(0,1,0)
				temp_eye = Geom::Point3d.new(0,0,100)
				cam.set(temp_eye,temp_target,temp_up)

				model = Sketchup.active_model
				defns = model.definitions
				profile_defn = defns.add(self.name)
				ents = profile_defn.entities
				self.draw(ents,true)
				profile_defn.set_attribute(@dict,@key,self.to_s)

				filename += ".skp" unless filename.end_with?(".skp")
				profile_defn.save_as(filename)
				cam.set(eye,target,up)
			end


			def load_from_skp(skp)

				begin
					Sketchup.active_model.start_operation("Import Shape", true)
					su_defn = import_component(skp)
					load_from_defn(su_defn)

					pb_material = ProfileMaterial.new(self.material_name)
					Sketchup.active_model.abort_operation

					Sketchup.active_model.start_operation("Import Shape", true)
					profile_material = pb_material.to_su_material()
					if profile_material
						self.material_name = profile_material.name
					else
						self.material_name = "Default"
					end
					l_name = self.layer_name
					if l_name
						Sketchup.active_model.layers.add(l_name)
					end
					Sketchup.active_model.commit_operation
				rescue IOError
					Sketchup.active_model.abort_operation
					VBO::ShapeForge.save_last_profile_path("")
					UI.messagebox("Invalid SketchUp Component File")
					return false
				rescue InvalidProfileSKP => err
					VBO::ShapeForge.save_last_profile_path("")
					Sketchup.active_model.abort_operation
					UI.messagebox(err.message)
					return false
				end

				return true

			end



			def clone
				cloned_profile=Shape.new(self.to_s)
				cloned_profile.x_scale=self.x_scale
				cloned_profile.y_scale=self.y_scale
				return cloned_profile
			end
			def reduce_polyline(po, delta = 1.mm, closed = true)
				i = 2
				while (i < po.length - 1)
					len = po[i-1].distance(po[i])
					if len < delta
						# merge 2 points to the mid point
						mid_point = Geom.linear_combination(0.5, po[i-1], 0.5, po[i])
						mid_point.z = 0
						po[i - 1] = mid_point
						po.delete_at(i)
					end
					i += 1
				end

				if closed
					if po[0].to_a != po[-1].to_a
						po << po[0]
					else
						po.pop if po[0].to_a == po[-1].to_a
					end
				end
				po.uniq{|c| c.to_a}
			end

			def reduce_profile
				@outer_loop = reduce_polyline(@outer_loop)
				@holes.each {|hole| hole = reduce_polyline(hole)}
			end

			def profile=(object)

				auto_reverse = false
				if object.is_a? Sketchup::Face
						su_face = object
						normal = su_face.normal
						box = su_face.bounds
						origin = box.center
						if origin.z == 0.0 and normal.samedirection?(Z_AXIS.reverse)
							auto_reverse=true
							normal.reverse!
						end
						trans = Geom::Transformation.new(origin, normal)
						trans.invert!
						@holes = []
						loops = su_face.loops
						loops.each {|loop|
							verts = loop.vertices
							verts.reverse! if auto_reverse
							if loop.outer?
								@outer_loop=verts.collect {|v| v.position.transform(trans)}

							else
								hole = []
								hole = verts.collect {|v| v.position.transform(trans)}
								@holes.push(hole)
							end
						}
						self.material_name = su_face.material.nil? ? 'Default' : su_face.material.name
						self.layer_name = su_face.layer.name
						@dimension = 2
				else
						normal = Geom::Vector3d.new(0,0,1)
						box = Geom::BoundingBox.new
						object.each {|p| box.add(p)}
						origin = box.center
						trans = Geom::Transformation.new(origin, normal)
						trans.invert!
						@outer_loop = object.collect {|p| p.transform(trans)}
						@dimension = 1
				end

			end

			def ==(value)
				to_s == value.to_s
			end

			def set_from_profile_member(pm)

				pm_profile=pm.profile
				self.points=pm_profile.points
				@holes=pm_profile.holes
				@dimension=pm_profile.dimension
				self.name=pm_profile.name
				self.placement_point=pm.placement_point
				self.rotation=pm.rotation
				self.x_offset=pm.x_offset
				self.y_offset=pm.y_offset
				self.smooth_angle=pm.smooth_angle
				@mirror=pm.mirror
				self.x_scale=pm.x_scale
				self.y_scale=pm.y_scale
				self.material_name = pm.material_name
				self.layer_name = pm.layer_name

			end


			def name=(new_name)
				@name = new_name.to_s.gsub("\n","%20").gsub(" ","%20")
			end

			def name
				@name
			end

			def fullname
				"#{@name.gsub('%20', ' ')} - #{self.width.to_l.to_s.gsub("~","")} x #{self.height.to_l.to_s.gsub("~","")}"
			end

			def points
				return @outer_loop.dup
			end

			def outer_loop

				return self.points

			end

			def points=(pts)

				@outer_loop=pts

			end

			def add_hole(pts)

				@holes.push(pts)

			end

			def holes
				return @holes
			end

			def dimension

				return @dimension

			end

			def is_2d?

				@dimension == 2

			end

			def is_1d?

				@dimension == 1

			end

			def area(trans = Geom::Transformation.new)

				outer_loop=self.points.collect {|p| p.transform(trans)}
				t_holes=[]
				self.holes.each {|hole|
					hole=hole.collect {|p| p.transform(trans)}
					t_holes.push(hole)
				}

				v1=outer_loop[1]-outer_loop[0]
				v2=outer_loop[2]-outer_loop[1]
				normal=v1.cross(v2).normalize!

				origin=Geom::Point3d.new(0,0,0)
				trans2=Geom::Transformation.new(origin,normal)
				trans2.invert!

				outer_loop_area=self.polygon_area(outer_loop,trans2)
				hole_area=0.0
				t_holes.each {|hole| hole_area+=self.polygon_area(hole,trans2)}
				return outer_loop_area+hole_area   #hole area has opposite sign

			end

			def default_width

				box=Geom::BoundingBox.new
				box.add(@outer_loop)
				return box.width
			end

			def default_height
				box=Geom::BoundingBox.new
				box.add(@outer_loop)
				return box.height
			end

			def width

				return default_width*x_scale

			end

			def height

				return default_height*y_scale

			end

			def scaled?

				scaled=false
				if self.x_scale!=1.0 or self.y_scale!=1.0
					scaled=true
				end
				scaled

			end

			def get_transformed_loop(profile_pts)
				#puts profile_pts.to_s
				t1 = transform_by_placement_point(@outer_loop, @placement_point)
				profile_pts = profile_pts.collect {|p| p.transform(t1)}
				t = transform_by_size(width,height,@x_scale,@y_scale)
				profile_pts = profile_pts.collect {|p| p.transform(t)}
				t2 = transform_by_rotation(profile_pts,@rotation)
				profile_pts = profile_pts.collect {|p| p.transform(t2)}
				t4 = transform_by_offset(profile_pts,@x_offset,@y_offset)
				profile_pts = profile_pts.collect {|p| p.transform(t4)}

				if @mirror
					t3 = transform_by_mirror(profile_pts)
					profile_pts = profile_pts.collect {|p| p.transform(t3)}
					profile_pts.reverse! #if is_hole
				end

				return profile_pts

			end

			def loops
				[@outer_loop] + @holes
			end

			def to_s

				points = @outer_loop.to_a.map{|p| "#{p.x.to_f} #{p.y.to_f}"}.join(" ")
				string = "#{@name} #{points}"

				# @holes.each {|hole|
				# 	hole_pts=[]
				# 	hole.each {|p|
				# 		hole_pts.push("#{p.x.to_f} #{p.y.to_f}")
				# 	}
				# 	hole_pts=hole_pts.join(" ")
				# 	hole_string="|#{hole_pts}"
				# 	string+=hole_string
				# }
				holes_strings = @holes.to_a.map{|hole| hole.map{|p| "#{p.x.to_f} #{p.y.to_f}"}.join(" ")}.join("|")
				string += "|#{holes_strings}"
				string+="|extended|#{@placement_point}|#{@mirror.to_s}|#{@rotation}|#{@x_offset}|#{@y_offset}|#{@smooth_angle}|#{@x_scale}|#{@y_scale}|#{@dimension}|#{@material_name}|#{@layer_name}|#{@junction_style}|#{@extrude_mode}"

				string+="\n"
				return string
			end

			def preview_dimensions(p1, p2, text, dim_ext = 5, dim_off = 30, dash = 3, align = 0, color = "#3391FF")
				case align
				when 0
					dim_vec = p1.vector_to(p2)
					ext_vec = dim_vec * Z_AXIS
					ext_vec.reverse! if @mirror
					return if ext_vec.length == 0
					ext1 = p1.offset(ext_vec,dim_off + dim_ext)
					ext2 = p2.offset(ext_vec,dim_off + dim_ext)

					dim_line = [
						p1.offset(dim_vec, - dim_ext).offset(ext_vec,dim_off).to_a[0..1].map{|x| x.to_i},
						p2.offset(dim_vec, dim_ext).offset(ext_vec,dim_off).to_a[0..1].map{|x| x.to_i}
					]
					ext1_line = [
						p1.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext1.to_a[0..1].map{|x| x.to_i}
					]
					ext2_line = [
						p2.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext2.to_a[0..1].map{|x| x.to_i}
					]
					dash1 = [
						p1.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).to_a[0..1].map{|x| x.to_i},
						p1.offset(dim_vec, dash).offset(ext_vec,dim_off + dash ).to_a[0..1].map{|x| x.to_i},
					]
					dash2 = [
						p2.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).to_a[0..1].map{|x| x.to_i},
						p2.offset(dim_vec, dash).offset(ext_vec,dim_off + dash ).to_a[0..1].map{|x| x.to_i},
					]
				when 1
					dim_vec = X_AXIS.clone
					dim_vec.reverse! if p1.x > p2.x
					ext_vec = dim_vec * Z_AXIS
					ext_vec.reverse! if @mirror
					ext_vec.reverse!
					ext1 = p1.offset(ext_vec,dim_off + dim_ext).to_a
					ext2 = [p2.x, ext1.y]
					dim_line = [
						p1.offset(dim_vec, - dim_ext).offset(ext_vec, dim_off).to_a[0..1],
						[
							p2.offset(dim_vec, dim_ext).x.to_i,
							p1.offset(dim_vec, - dim_ext).offset(ext_vec,dim_off).y.to_i
						]
					]
					ext1_line = [
						p1.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext1.to_a[0..1].map{|x| x.to_i}
					].flatten
					ext2_line = [
						p2.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext2.to_a[0..1].map{|x| x.to_i}
					].flatten
					dash1 = [
						p1.offset(dim_vec, - dash).offset(ext_vec,dim_off + dash).to_a[0..1].map{|x| x.to_i},
						p1.offset(dim_vec, dash).offset(ext_vec,dim_off - dash ).to_a[0..1].map{|x| x.to_i},
					]
					dash2 = [
						[
							p2.offset(dim_vec, dash).offset(ext_vec,dim_off + dash).x.to_i,
							dash1[1].y,
						],
						[
							p2.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).x.to_i,
							dash1[0].y,
						]
					]
				when 2
					dim_vec = Y_AXIS.clone
					dim_vec.reverse! if p1.y > p2.y
					ext_vec = dim_vec * Z_AXIS
					ext_vec.reverse! if @mirror
					ext1 = p1.offset(ext_vec,dim_off + dim_ext).to_a.map{|x| x.to_i}
					ext2 = [ext1.x, p2.y]
					dim_line = [
						p1.offset(dim_vec, - dim_ext).offset(ext_vec, dim_off).to_a[0..1].map{|x| x.to_i},
						[
							p1.offset(dim_vec, - dim_ext).offset(ext_vec,dim_off).x.to_i,
							p2.offset(dim_vec, dim_ext).y.to_i
						]
					]
					ext1_line = [
						p1.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext1.to_a[0..1].map{|x| x.to_i}
					].flatten
					ext2_line = [
						p2.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext2.to_a[0..1].map{|x| x.to_i}
					].flatten
					dash1 = [
						p1.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).to_a[0..1].map{|x| x.to_i},
						p1.offset(dim_vec, dash).offset(ext_vec,dim_off + dash ).to_a[0..1].map{|x| x.to_i},
					]
					dash2 = [
						[
							dash1[0].x,
							p2.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).y.to_i,
						],
						[
							dash1[1].x,
							p2.offset(dim_vec, dash).offset(ext_vec,dim_off + dash).y.to_i,
						]
					]
				end

				script = %Q{
					jg.setStroke(1);
					jg.setColor("#{color}");

					jg.drawLine(#{ext1_line.join(',')});
					jg.drawLine(#{ext2_line.join(',')});
				}
				id, dimension = text.split('|')

				script += %Q{
					jg.drawLine(#{dim_line.join(',')});
					jg.setStroke(2);
					jg.drawLine(#{dash1.join(',')});
					jg.drawLine(#{dash2.join(',')});
				} if dimension && dimension.delete('~').to_l.to_f != 0
				dim_pos = dim_line.map{|c| c.offset(ext_vec,14)}.transpose.map{|c| ((c[0] + c[1]) / 2.0).to_i}
				ang = clock_wise_angle(dim_vec, X_AXIS).radians.round(0) % 180
				ang += 180 if ang >= 90
				ang = 0 if id == 'height'
				ang = 0 if id == 'width'
				script2 = ""
				if id
					script2 = dimension ? %Q{
						if (#{dimension.to_l.to_f} == 0) {
							$("##{id}").html(`<i class="fa fa-arrows-h" ></i><br>0`);
						}else{
							$("##{id}").text(`#{dimension.delete('~')}`);
						}
					} : ""
					script2 += %Q{
						var lx = $("##{id}").width();
						var ly = $("##{id}").height();
						$("##{id}").css({
							display: 'block',
							cursor: 'text',
							top: #{dim_pos.y} - ly/2,
							left: #{dim_pos.x} - lx/2,
							position:'absolute',
							transform: 'rotate(#{-ang}deg)',
							'font-size': 12,
							'font-family': 'Arial',
							'font-weight': 'bold',
							'text-alignment': 'center',
							'z-index': 101,
							color: '#{color}'
						});

						var #{id}_contents = $("##{id}").text();
						$("##{id}").blur(function() {
							if (#{id}_contents!=$(this).text()){
								#{id}_contents = $(this).text();
								sketchup.change("#{id}",#{id}_contents);
							}
						});
					}
				end
				s = script + script2
				s
			end

			def preview_dimensions2(p1, p2, text, dim_ext = 5, dim_off = 30, dash = 3, align = 0, color = "#3391FF")
				case align
				when 0
					dim_vec = p1.vector_to(p2)
					ext_vec = dim_vec * Z_AXIS
					ext_vec.reverse! if @mirror
					return if ext_vec.length == 0
					ext1 = p1.offset(ext_vec,dim_off + dim_ext)
					ext2 = p2.offset(ext_vec,dim_off + dim_ext)

					dim_line = [
						p1.offset(dim_vec, - dim_ext).offset(ext_vec,dim_off).to_a[0..1].map{|x| x.to_i},
						p2.offset(dim_vec, dim_ext).offset(ext_vec,dim_off).to_a[0..1].map{|x| x.to_i}
					]
					ext1_line = [
						p1.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext1.to_a[0..1].map{|x| x.to_i}
					]
					ext2_line = [
						p2.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext2.to_a[0..1].map{|x| x.to_i}
					]
					dash1 = [
						p1.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).to_a[0..1].map{|x| x.to_i},
						p1.offset(dim_vec, dash).offset(ext_vec,dim_off + dash ).to_a[0..1].map{|x| x.to_i},
					]
					dash2 = [
						p2.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).to_a[0..1].map{|x| x.to_i},
						p2.offset(dim_vec, dash).offset(ext_vec,dim_off + dash ).to_a[0..1].map{|x| x.to_i},
					]
				when 1
					dim_vec = X_AXIS.clone
					dim_vec.reverse! if p1.x > p2.x
					ext_vec = dim_vec * Z_AXIS
					ext_vec.reverse! if @mirror
					ext_vec.reverse!
					ext1 = p1.offset(ext_vec,dim_off + dim_ext).to_a
					ext2 = [p2.x, ext1.y]
					dim_line = [
						p1.offset(dim_vec, - dim_ext).offset(ext_vec, dim_off).to_a[0..1],
						[
							p2.offset(dim_vec, dim_ext).x.to_i,
							p1.offset(dim_vec, - dim_ext).offset(ext_vec,dim_off).y.to_i
						]
					]
					ext1_line = [
						p1.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext1.to_a[0..1].map{|x| x.to_i}
					].flatten
					ext2_line = [
						p2.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext2.to_a[0..1].map{|x| x.to_i}
					].flatten
					dash1 = [
						p1.offset(dim_vec, - dash).offset(ext_vec,dim_off + dash).to_a[0..1].map{|x| x.to_i},
						p1.offset(dim_vec, dash).offset(ext_vec,dim_off - dash ).to_a[0..1].map{|x| x.to_i},
					]
					dash2 = [
						[
							p2.offset(dim_vec, dash).offset(ext_vec,dim_off + dash).x.to_i,
							dash1[1].y,
						],
						[
							p2.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).x.to_i,
							dash1[0].y,
						]
					]
				when 2
					dim_vec = Y_AXIS.clone
					dim_vec.reverse! if p1.y > p2.y
					ext_vec = dim_vec * Z_AXIS
					ext_vec.reverse! if @mirror
					ext1 = p1.offset(ext_vec,dim_off + dim_ext).to_a.map{|x| x.to_i}
					ext2 = [ext1.x, p2.y]
					dim_line = [
						p1.offset(dim_vec, - dim_ext).offset(ext_vec, dim_off).to_a[0..1].map{|x| x.to_i},
						[
							p1.offset(dim_vec, - dim_ext).offset(ext_vec,dim_off).x.to_i,
							p2.offset(dim_vec, dim_ext).y.to_i
						]
					]
					ext1_line = [
						p1.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext1.to_a[0..1].map{|x| x.to_i}
					].flatten
					ext2_line = [
						p2.offset(ext_vec,2 * dim_ext).to_a[0..1].map{|x| x.to_i},
						ext2.to_a[0..1].map{|x| x.to_i}
					].flatten
					dash1 = [
						p1.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).to_a[0..1].map{|x| x.to_i},
						p1.offset(dim_vec, dash).offset(ext_vec,dim_off + dash ).to_a[0..1].map{|x| x.to_i},
					]
					dash2 = [
						[
							dash1[0].x,
							p2.offset(dim_vec, - dash).offset(ext_vec,dim_off - dash).y.to_i,
						],
						[
							dash1[1].x,
							p2.offset(dim_vec, dash).offset(ext_vec,dim_off + dash).y.to_i,
						]
					]
				end

				script = %Q{
					jg.setStroke(1);
					jg.setColor("#{color}");

					jg.drawLine(#{ext1_line.join(',')});
					jg.drawLine(#{ext2_line.join(',')});
				}
				id, dimension = text.split('|')

				script += %Q{
					jg.drawLine(#{dim_line.join(',')});
					jg.setStroke(2);
					jg.drawLine(#{dash1.join(',')});
					jg.drawLine(#{dash2.join(',')});
				} if dimension && dimension.delete('~').to_l.to_f != 0
				dim_pos = dim_line.map{|c| c.offset(ext_vec,14)}.transpose.map{|c| ((c[0] + c[1]) / 2.0).to_i}
				ang = clock_wise_angle(dim_vec, X_AXIS).radians.round(0) % 180
				ang += 180 if ang >= 90
				script2 = ""
				if id
					script2 = dimension ? %Q{
						if (#{dimension.to_l.to_f} == 0) {
							$("##{id}").html(`<i class="fa fa-arrows-h" ></i><br>0`);
						}else{
							$("##{id}").text(`#{dimension.delete('~')}`);
						}
					} : ""
					script2 += %Q{
						var lx = $("##{id}").width();
						var ly = $("##{id}").height();
						$("##{id}").css({
							display: 'block',
							cursor: 'text',
							top: #{dim_pos.y} - ly/2,
							left: #{dim_pos.x} - lx/2,
							position:'absolute',
							transform: 'rotate(#{-ang}deg)',
							'font-size': 12,
							'font-family': 'Arial',
							'font-weight': 'bold',
							'text-alignment': 'center',
							'z-index': 101,
							color: '#{color}'
						});

						var #{id}_contents = $("##{id}").text();
						$("##{id}").blur(function() {
							if (#{id}_contents!=$(this).text()){
								document.body.style.cursor = 'wait';
								if (isGridLocked('profile_grid')) {
									#{id}_span_contents = $(this).text();
									sketchup.change("#{id}_span",[#{id}_span_contents, w2ui.span_grid.getSelection()[0]], {
										onCompleted: function() {
											document.body.style.cursor = temp_cursor;
										}});
								} else {
									#{id}_contents = $(this).text();
									sketchup.change("#{id}",[#{id}_contents, w2ui.profile_grid.getSelection()[0]], {
										onCompleted: function() {
											document.body.style.cursor = temp_cursor;
										}});
								}
							}
						});
					}
				end
				s = script + script2
				s
			end

			def color_to_hex(color)
				'#' + ('%02x%02x%02x' % Sketchup::Color.new(color).to_a).upcase
			end

			def preview(dialog, compare = nil, red='')
				profile = self
				width = dialog.get_content_size.min  - 35
				canvas =  width * 0.72
				cent = (canvas.to_f/2.0).to_i


				origin = Geom::Point3d.new(0,0,0)
				center = Geom::Point3d.new(cent,cent * 1.2,0)

				pts = profile.outer_loop
				pts = profile.get_transformed_loop(pts)
				preview_origin = Geom::Point3d.new(0,0,0)

				if compare
					com_pts = []
					com_preview_origin = []
					compare.to_a.each{|comp|
						com_pts << comp.get_transformed_loop(comp.points)
						com_preview_origin << Geom::Point3d.new(0,0,0)
					}

				end

				box = Geom::BoundingBox.new
				box.add(pts)
				box.add(preview_origin)

				if compare
					box.add(com_pts.flatten)
					box.add(com_preview_origin)
				end

				profile_bounds = Geom::BoundingBox.new.add(self.outer_loop)
				b_table = self.get_transformed_loop((0..3).to_a.map{|c| profile_bounds.corner(c).to_a})
				grid = VBO::ShapeForge.align_table(b_table)

				mirror_trans = Geom::Transformation.scaling(grid[4], - 1, -1, 1)
				grid = grid.map{|c| c.transform(mirror_trans)} if @mirror


				box.add(grid)
				vec = center-box.center

				trans1 = Geom::Transformation.translation(vec)

				new_points = pts.map{|point| point.transform(trans1)}
				preview_origin = preview_origin.transform(trans1)
				grid = grid.map{|c| c.transform(trans1)} #testing preview placement point

				if compare
					com_new_points = com_pts.map{|comp| comp.map{|c| c.transform(trans1)}}
					com_preview_origin.map!{|c| c.transform(trans1)}
				end

				box = Geom::BoundingBox.new
				box.add(new_points)
				box.add(preview_origin)  #new
				box.add(grid)

				if compare
					box.add(com_new_points.flatten)
					box.add(com_preview_origin)
				end

				xmax = box.max.x-box.min.x
				ymax = box.max.y-box.min.y
				xymax = [xmax,ymax].max.to_f
				scale = (canvas.to_f/xymax)*0.65

				ratio = xmax / ymax
				# UI.messagebox(ratio.to_s)
				trans2 = if ratio > 6 || ratio <  1/6.0
					# UI.messagebox("Shape is too wide or too tall to be displayed properly. Please use the 'Preview' button to see the profile.")
					balance = true
					if xmax > ymax
						Geom::Transformation.scaling(center, scale, - (xmax / 6.0) * scale / ymax, scale)
					else
						Geom::Transformation.scaling(center, (ymax / 6.0) * scale / xmax, -scale,  scale)
					end
				else
					balance = false
					Geom::Transformation.scaling(center, scale, - scale, scale)
				end

				new_points = new_points.map{|point| point.transform(trans2)}
				grid = grid.map{|c| c.transform(trans2)}
				preview_origin = preview_origin.transform(trans2)

				if compare
					com_new_points.map!{|comp| comp.map{|c| c.transform(trans2)}}
					com_preview_origin.map!{|c| c.transform(trans2)}
				end

				box = Geom::BoundingBox.new
				box.add(new_points)
				box.add(preview_origin)
				box.add(grid)

				if compare
					box.add(com_new_points.flatten)
					box.add(com_preview_origin)
					#puts com_new_points.flatten.to_s
				end

				maxArc_angle = [@rotation, 90].min_by{|x| x.abs}.degrees
				maxArc_point = Geom::Point3d.new([
					preview_origin.x - width * 0.14 * Math.sin(maxArc_angle),
					preview_origin.y - width * 0.14 * Math.cos(maxArc_angle),
					0
				])
				box.add(maxArc_point)

				dialog.execute_script(%Q{$("#Canvas").height(#{box.height.to_i});})


				xpoints, ypoints, zpoints = new_points.map{|point| point.to_a.map{|c| c}}.transpose
				x_array = "new Array(#{xpoints.join(",")})"
				y_array = "new Array(#{ypoints.join(",")})"

				# puts "profile points: #{new_points}"
				send_to_ov = {
					section: [new_points],
					grid: grid,
					origin: preview_origin,
					width: width,
					box: box,
					shape: self
				}

				if compare
					com_x_array = []
					com_y_array = []
					com_new_points.each{|comp|
						com_xpoints, com_ypoints, com_zpoints = comp.map{|point| point.to_a.map{|c| c}}.transpose
						com_x_array << "new Array(#{com_xpoints.join(",")})"
						com_y_array << "new Array(#{com_ypoints.join(",")})"
					}
				end
				cmd =  %Q{
					clearCanvas();
					$('#profile_name').text('#{self.name.include?('Selection') ? self.name.gsub('*_*', ' ').gsub("%20", " ") : self.name.gsub('*_*', ' ').gsub("%20", " ")}');
					profile_name = '#{self.name.gsub('*_*', ' ').gsub("%20", " ")}';
					$('#profile_name').css('display','block');
				}

				model = Sketchup.active_model
				options = model.rendering_options
				color_by_layer = options["DisplayColorByLayer"]
				background = options["BackgroundColor"]
				face_front = options["FaceFrontColor"]
				face_back = options["FaceBackColor"]
				edge_color = 'black'
				edge_width = options["SectionCutWidth"]

				if @name == 'No_Selection'
					edge_color = 'red'
					color = Sketchup::Color.new('red')
				elsif color_by_layer
					layer = model.layers[@layer_name]
					# puts "layer: #{layer}"
					color = layer ? layer.color : Sketchup::Color.new('white')
				else
					material = model.materials[@material_name]
					if material
						# if material.texture
						# 	color = Sketchup::Color.new('#cccccc')
						# else
							color = material.color
							color.alpha = material.alpha
						# end
					else
						color = Sketchup::Color.new('white')
					end
				end

				#puts x_array
				cmd += %Q{
					drawProfile(#{x_array},#{y_array}, false,'#000000', '#{color_to_hex(color)}');
				} if profile.is_2d?
				cmd += %Q{
					drawPolyline(#{x_array},#{y_array});
				} if profile.is_1d?

				profile.holes.each {|hole|
					#new code for rotation,mirror, and offset
					hole = profile.get_transformed_loop(hole)

					new_hole = hole.map{|point| point.transform(trans1)}
					new_hole.push(hole[0].transform(trans1))  #add first point to close the loop
					new_hole = new_hole.map{|point| point.transform(trans2)}

					send_to_ov[:section] << new_hole

					xpoints, ypoints, zpoints = new_hole.map{|point| point.to_a.map{|c| c.to_i}}.transpose

					x_array = "new Array(#{xpoints.join(",")})"
					y_array = "new Array(#{ypoints.join(",")})"

					cmd += %Q{
						drawHole(#{x_array},#{y_array}, '#{red}');
					}
				}

				if compare
					#puts com_x_array
					com_x_array.each_index{|i|
						cmd += %Q{
							drawProfile(#{com_x_array[i]},#{com_y_array[i]}, true);
						} if compare.to_a[i].is_2d?
						cmd += %Q{
							drawPolyline(#{com_x_array[i]},#{com_y_array[i]}, true);
						} if compare.to_a[i].is_1d?
					}
				end

				if self.name != 'No_Selection'
					grid.each_with_index{|po, i|
						x = po.x - 7
						y = po.y - 7
						cmd += %Q{
							$("#radio_#{i}").css({top: #{y.to_i - 2}, left: #{x.to_i - 4}, position:'absolute'});
						}

							cmd += %Q{
								//console.log(`${parseInt($("#radio_#{i}").val())} = #{i}`);
								if (parseInt($("#radio_#{i}").val()) + 1 == #{self.placement_point}) {
									$("#radio_#{i}").prop("checked", true);
								}
							}

					}
					mir = [6,7,8,3,4,5,0,1,2]
					if !grid.include?(preview_origin)
						x = preview_origin.x - 6
						y = preview_origin.y - 6
						o_color_x = "red"
						o_color_y = "green"
						cmd += %Q{
							$("#origin").css({
								display: 'block',
								top: #{y.to_i},
								left: #{x.to_i},
								position:'absolute',
								'z-index': 101,
							});

							$("#origin").on('mouseover', function(){
								show_tooltip($(this),"Base Point")
							});

							$("#origin").on('mouseleave', function(){
								show_tooltip($(this),"")
							});

							#{
								plm = grid[mir[self.placement_point - 1]]

									if preview_origin.x > plm.x && self.rotation > 0
										preview_dimensions(preview_origin, plm, "x_offset|#{self.x_offset.to_l.to_s}", 5, width * 0.08, 3, 1, o_color_x) + "\n" + preview_dimensions(preview_origin, plm, "y_offset|#{self.y_offset.to_l.to_s}", 5, width * 0.08, 3, 2, o_color_y)
									else
										preview_dimensions(preview_origin, plm, "x_offset|#{self.x_offset.to_l.to_s}", 5, width * 0.08, 3, 1, o_color_x) + "\n" + preview_dimensions(plm, preview_origin, "y_offset|#{self.y_offset.to_l.to_s}", 5, width * 0.08, 3, 2, o_color_y)
									end
							}
						}
					end
					cmd += %Q{
						#{
							if red == ''
								preview_dimensions(grid[0], grid[6], "height|#{self.height.to_l.to_s}", 5, width * 0.08)
							else
								preview_dimensions(grid[0], grid[6], "height|1", 5, width * 0.08)
							end
						}
						#{
							if red == ''
								preview_dimensions(grid[6], grid[8], "width|#{self.width.to_l.to_s}", 5, width * 0.08)
							else
								preview_dimensions(grid[6], grid[8], "width|1", 5, width * 0.08)
							end
						}
						//origin



						// mirror axes
						var y1 = -30;
						var x1 = #{box.center.x.to_i};
						jg.setStroke(1);
						jg.setColor("green");
						while (y1 < #{(box.max.y + 30).to_i}){
								var y2 = y1 + 12;
								jg.drawLine(x1,y1,x1,y2);
								y1 = y2 + 8;
								y2 = y1 + 3;
								jg.drawLine(x1,y1,x1,y2);
								y1 = y2 + 8;
						}
						var canvasW = $("#Canvas").width();
						var btnGap = canvasW / 5;
						var centerX = canvasW / 2;
						// mirror icon
						mirror = #{@mirror};
						$("#mirror").css({
							display: 'block',
							top: -30,
							left: centerX - 12 + 4.5,
							position:'absolute',
							'background-color': '#{@mirror ? "red" : "white"}',
							'z-index': 101,
						});
						$("#mirror").on('mouseover', function(){
							show_tooltip($("#mirror"),"#{@mirror ? "Mirrored" : "Not mirrored"}")
							$(this).css('background-color','#{@mirror ? "red" : "white"}')
						});
						$("#mirror").on('mouseleave', function(){
							show_tooltip($("#mirror"),"");
							$(this).css('background-color','#{@mirror ? "red" : "white"}')
						});
						// material and layer
						$("#material_name").css({
							display: 'block',
							top: -30,
							left: centerX - btnGap - 7,
							position:'absolute',
							'z-index': 102,
						});
						$("#layer_name").css({
							display: 'block',
							top: -30,
							left: centerX + btnGap - 7,
							position:'absolute',
							'z-index': 102,
						});

						//rotation arc
						drawArc(#{preview_origin.x.to_i}, #{preview_origin.y.to_i}, #{@mirror ?  - self.rotation : self.rotation}, #{width * 0.14});

						jg.paint();
						$('input:radio').show();

						//profiles stack

						$("#undo").css({
							display: 'block',
							top: -30,
							left: centerX - 2 * btnGap - 7,
							position:'absolute',
							'z-index': 102,
						});

						$("#redo").css({
							display: 'block',
							top: -30,
							left: centerX + 2 * btnGap - 7,
							right: 'auto',
							position:'absolute',
							'z-index': 102,
						});



						$('#profile_name').prop('contenteditable', 'true');

						//profile_toolbar
						//place_toolbar("profile_toolbar", #{(box.max.y + 50).to_i});
						$("#profile_toolbar").css({
							display: 'block',
						});
						place_toolbar("member_toolbar", #{(box.max.y + 65).to_i});
						selective_top = #{(box.max.y + 340).to_i};
						if ($('#selective').css('display') == 'block') {
							$('#selective').css({'top': selective_top});
						}
					}
				else
					cmd += %Q{
						place_toolbar("member_toolbar", #{(box.max.y + 85).to_i});
						$('#profile_name').prop('contenteditable', 'false');
						jg.paint();
					}
				end
				if @extrude_mode == "normal_mode"
					cmd += %Q{
						w2ui.profile_toolbar.set('extrude_mode', { tooltip: 'Normal Mode' });
						w2ui.profile_toolbar.check('extrude_mode');
					}
				else
					cmd += %Q{
						w2ui.profile_toolbar.set('extrude_mode', { tooltip: 'Follow Me Mode' });
						w2ui.profile_toolbar.uncheck('extrude_mode');
					}
				end
				VBO::ShapeForge.send_to_overlay(send_to_ov)
				dialog.execute_script(cmd)
				#puts grid.to_s
			end

			def preview2(dialog, compare = nil, red='')
				# VBO::ShapeForge.debug "preview2 : #{self.name}"
				profile = self
				width = 260#dialog.get_content_size.min  - 15
				canvas =  width * 0.4
				cent = (canvas.to_f/2.0).to_i + (width * 0.3).to_i


				origin = Geom::Point3d.new(0,0,0)
				center = Geom::Point3d.new(cent * 0.9,cent * 0.85,0)

				pts = profile.outer_loop
				pts = profile.get_transformed_loop(pts)
				preview_origin = Geom::Point3d.new(0,0,0)

				if compare
					com_pts = []
					com_preview_origin = []
					compare.to_a.each{|comp|
						com_pts << comp.get_transformed_loop(comp.points)
						com_preview_origin << Geom::Point3d.new(0,0,0)
					}

				end

				box = Geom::BoundingBox.new
				box.add(pts)
				box.add(preview_origin)

				if compare && !compare.empty?
					box.add(com_pts.flatten)
					box.add(com_preview_origin)
				end

				profile_bounds = Geom::BoundingBox.new.add(self.outer_loop)
				b_table = self.get_transformed_loop((0..3).to_a.map{|c| profile_bounds.corner(c).to_a})
				grid = VBO::ShapeForge.align_table(b_table)

				mirror_trans = Geom::Transformation.scaling(grid[4], - 1, -1, 1)
				grid = grid.map{|c| c.transform(mirror_trans)} if @mirror


				box.add(grid)
				vec = center-box.center

				trans1 = Geom::Transformation.translation(vec)

				new_points = pts.map{|point| point.transform(trans1)}
				preview_origin = preview_origin.transform(trans1)
				grid = grid.map{|c| c.transform(trans1)} #testing preview placement point

				if compare
					com_new_points = com_pts.map{|comp| comp.map{|c| c.transform(trans1)}}
					com_preview_origin.map!{|c| c.transform(trans1)}
				end

				box = Geom::BoundingBox.new
				box.add(new_points)
				box.add(preview_origin)  #new
				box.add(grid)

				if compare && !compare.empty?
					box.add(com_new_points.flatten)
					box.add(com_preview_origin)
				end

				xmax = box.max.x-box.min.x
				ymax = box.max.y-box.min.y
				xymax = [xmax,ymax].max.to_f
				scale = (canvas.to_f / xymax * 1.2)*0.65
				ratio = xmax / ymax
				# UI.messagebox(ratio.to_s)
				trans2 = if ratio > 5 || ratio < 0.2
					# UI.messagebox("Shape is too wide or too tall to be displayed properly. Please use the 'Preview' button to see the profile.")
					balance = true
					if xmax > ymax
						Geom::Transformation.scaling(center, scale, - (xmax / 5.0) * scale / ymax, scale)
					else
						Geom::Transformation.scaling(center, (ymax / 5.0) * scale / xmax, -scale,  scale)
					end
				else
					balance = false
					Geom::Transformation.scaling(center, scale, - scale, scale)
				end

				new_points = new_points.map{|point| point.transform(trans2)}
				grid = grid.map{|c| c.transform(trans2)}
				preview_origin = preview_origin.transform(trans2)

				if compare
					com_new_points.map!{|comp| comp.map{|c| c.transform(trans2)}}
					com_preview_origin.map!{|c| c.transform(trans2)}
				end

				box = Geom::BoundingBox.new
				box.add(new_points)
				box.add(preview_origin)
				box.add(grid)

				if compare && !compare.empty?
					box.add(com_new_points.flatten)
					box.add(com_preview_origin)
					#puts com_new_points.flatten.to_s
				end

				maxArc_angle = [@rotation, 90].min_by{|x| x.abs}.degrees
				maxArc_point = Geom::Point3d.new([
					preview_origin.x - width * 0.14 * Math.sin(maxArc_angle),
					preview_origin.y - width * 0.14 * Math.cos(maxArc_angle),
					0
				])
				box.add(maxArc_point)

				dialog.execute_script(%Q{$("#Canvas").height(#{box.height.to_i});})


				xpoints, ypoints, zpoints = new_points.map{|point| point.to_a.map{|c| c}}.transpose
				x_array = "new Array(#{xpoints.join(",")})"
				y_array = "new Array(#{ypoints.join(",")})"

				if compare && !compare.empty?
					com_x_array = []
					com_y_array = []
					com_new_points.each{|comp|
						com_xpoints, com_ypoints, com_zpoints = comp.map{|point| point.to_a.map{|c| c}}.transpose
						com_x_array << "new Array(#{com_xpoints.join(",")})"
						com_y_array << "new Array(#{com_ypoints.join(",")})"
					}
				end
				cmd =  %Q{
					clearCanvas();
					jg.clear();
				}
				#puts x_array
				cmd += %Q{
					drawProfile(#{x_array},#{y_array}, false,'#{red}');
				} if profile.is_2d?
				cmd += %Q{
					drawPolyline(#{x_array},#{y_array});
				} if profile.is_1d?

				profile.holes.each {|hole|
					#new code for rotation,mirror, and offset
					hole = profile.get_transformed_loop(hole)

					new_hole = hole.map{|point| point.transform(trans1)}
					new_hole.push(hole[0].transform(trans1))  #add first point to close the loop
					new_hole = new_hole.map{|point| point.transform(trans2)}


					xpoints, ypoints, zpoints = new_hole.map{|point| point.to_a.map{|c| c.to_i}}.transpose

					x_array = "new Array(#{xpoints.join(",")})"
					y_array = "new Array(#{ypoints.join(",")})"

					cmd += %Q{
						drawHole(#{x_array},#{y_array}, '#{red}');
					}
				}

				if compare && !compare.empty?
					#puts com_x_array
					com_x_array.each_index{|i|
						cmd += %Q{
							drawProfile(#{com_x_array[i]},#{com_y_array[i]}, true);
						} if compare.to_a[i].is_2d?
						cmd += %Q{
							drawPolyline(#{com_x_array[i]},#{com_y_array[i]}, true);
						} if compare.to_a[i].is_1d?
					}
				end

				if self.name != 'No_Selection'
					grid.each_with_index{|po, i|
						x = po.x - 7
						y = po.y - 7
						cmd += %Q{
							$("#radio_#{i}").css({top: #{y.to_i - 2}, left: #{x.to_i - 2}, position:'absolute'});
						}

							cmd += %Q{
								//console.log(`${parseInt($("#radio_#{i}").val())} = #{i}`);
								if (parseInt($("#radio_#{i}").val()) + 1 == #{self.placement_point}) {
									$("#radio_#{i}").prop("checked", true);
								}
							}

					}
					if compare.nil?
						mir = [6,7,8,3,4,5,0,1,2]
						if !grid.include?(preview_origin)
							x = preview_origin.x - 6
							y = preview_origin.y - 6
							o_color_x = "red"
							o_color_y = "green"
							cmd += %Q{
								$("#origin").css({
									display: 'block',
									top: #{y.to_i},
									left: #{x.to_i},
									position:'absolute',
									'z-index': 101,
								});

								$("#origin").on('mouseover', function(){
									show_tooltip($(this),"Base Point")
								});

								$("#origin").on('mouseleave', function(){
									show_tooltip($(this),"")
								});

								#{
									plm = grid[mir[self.placement_point - 1]]

										if preview_origin.x > plm.x && self.rotation > 0
											preview_dimensions2(preview_origin, plm, "x_offset|#{self.x_offset.to_l.to_s}", 5, width * 0.08, 3, 1, o_color_x) + "\n" + preview_dimensions2(preview_origin, plm, "y_offset|#{self.y_offset.to_l.to_s}", 5, width * 0.08, 3, 2, o_color_y)
										else
											preview_dimensions2(preview_origin, plm, "x_offset|#{self.x_offset.to_l.to_s}", 5, width * 0.08, 3, 1, o_color_x) + "\n" + preview_dimensions2(plm, preview_origin, "y_offset|#{self.y_offset.to_l.to_s}", 5, width * 0.08, 3, 2, o_color_y)
										end
								}
							}
						end
						cmd += %Q{
							#{
								if red == ''
									preview_dimensions2(grid[0], grid[6], "height|#{self.height.to_l.to_s}", 5, width * 0.08)
								else
									preview_dimensions2(grid[0], grid[6], "height|1", 5, width * 0.08)
								end
							}
							#{
								if red == ''
									preview_dimensions2(grid[6], grid[8], "width|#{self.width.to_l.to_s}", 5, width * 0.08)
								else
									preview_dimensions2(grid[6], grid[8], "width|1", 5, width * 0.08)
								end
							}
							//rotation arc
							drawArc(#{preview_origin.x.to_i}, #{preview_origin.y.to_i}, #{@mirror ?  - self.rotation : self.rotation}, #{width * 0.14});

							jg.paint();
							$('input:radio').show();
						}
					else
						x = preview_origin.x - 6
						y = preview_origin.y - 6
						o_color_x = "red"
						o_color_y = "green"
						cmd += %Q{
							$("#origin").css({
								display: 'block',
								top: #{y.to_i},
								left: #{x.to_i},
								position:'absolute',
								'z-index': 101,
							});

							$("#origin").on('mouseover', function(){
								show_tooltip($(this),"Base Point")
							});

							$("#origin").on('mouseleave', function(){
								show_tooltip($(this),"")
							});
							jg.paint();
						}
					end
				else
					cmd += %Q{
						jg.paint();
					}
				end
				dialog.execute_script(cmd)
			end

			#private

			class InvalidProfileSKP < RuntimeError

			end

			def randomid
				a = rand(5) + 1
				rand.to_s.slice(a..a+5)
			end
			def import_component(skp)

				defns=Sketchup.active_model.definitions
				su_defn=defns.load(skp)
				return su_defn

			end

			def add_point(p)
				@outer_loop.push(p)
			end

			def load_from_defn(su_defn)

				f = get_profile_face(su_defn)
				valid_path = get_valid_path(su_defn)

				if f or valid_path
					initialize(nil)
					load_attributes_from_defn(su_defn)
					if f
						profile_bounds = Geom::BoundingBox.new.add(f.outer_loop.vertices.map{|c| c.position})
						b_table = [2,3,0,1].map{|c| profile_bounds.corner(c).to_a}
						grid = VBO::ShapeForge.align_table(b_table).map{|c| c.to_a.map{|co| co.round(3)}}
						point = grid[@placement_point.to_i - 1]
						su_defn.entities.transform_by_vectors([f], [Geom::Vector3d.new(point).reverse])
						self.profile = f
						@material_name = f.material.nil? ? "Default" : f.material.name
						@layer_name = f.layer.name
						@x_offset, @y_offset, z = point.to_a
					elsif valid_path
						edges = valid_path
						verts = edges.collect {|edge| edge.vertices}
						verts.flatten!
						start_vert = verts.find {|v| v.get_attribute(@dict,'polyline_index')==0}
						pts_chain = Chain.new
						pts_chain.set(edges,start_vert)
						self.profile = pts_chain.path

						profile_bounds = Geom::BoundingBox.new.add(verts.map{|c| c.position})
						b_table = [2,3,0,1].map{|c| profile_bounds.corner(c).to_a}
						grid = VBO::ShapeForge.align_table(b_table)
						point = grid[@placement_point.to_i - 1]
						@layer_name = edges[0].layer.name
						@x_offset, @y_offset, z = point.to_a

					end
					self.name = File.basename(su_defn.path,".skp") if self.name == ""
				else
					raise InvalidProfileSKP, "Sorry, a valid Shape only contains one face or polyline!",caller
				end
				return true
			end

			def to_group(trans)
				g = Sketchup.active_model.active_entities.add_group
				g = g.to_component
				g.set_attribute("VBO ShapeForge", "Shape Temporary", true)
				draw(g.definition.entities)
				g.definition.set_attribute(@dict,@key,self.to_s)
				g.transformation = trans
				g
			end
			def draw(ents, use_pb_default = false)
				mats=Sketchup.active_model.materials
				mat=mats[@material_name]

				if self.is_2d?
					outer_loop = get_transformed_loop(@outer_loop)
					face = ents.add_face(outer_loop)
					face.reverse!
					face.material = mat
					face.layer = Sketchup.active_model.layers.add @layer_name
					@holes.each{|hole|
						f = ents.add_face(hole.reverse)
						f.erase!
					}
				else
					outer_loop = get_transformed_loop(@outer_loop)
					curve_group  =ents.add_group
					curve_group.entities.add_curve(outer_loop)
					a = curve_group.explode
					a.each{|c| c.layer = Sketchup.active_model.layers.add @layer_name}
				end
				profile_bounds = Geom::BoundingBox.new.add(outer_loop)
				b_table = [2,3,0,1].map{|c| profile_bounds.corner(c).to_a}
				grid = VBO::ShapeForge.align_table(b_table)
				point = grid[@placement_point.to_i - 1]
				#grid.each{|pt| ents.add_cpoint(pt) if pt!= point}
				ents.add_cpoint(point)
				#ents.transform_by_vectors(ents, [-@x_offset, - @y_offset, 0])
				#ents.transform_by_vectors(ents, Geom::Vector3d.new(point.to_a).reverse)
			end

			def draw_(ents, use_pb_default = false)
				mats=Sketchup.active_model.materials
				mat=mats[@material_name]

				if self.is_2d?
					outer_loop = @outer_loop
					face = ents.add_face(outer_loop)
					face.reverse!
					face.material = mat
					@holes.each{|hole|
						f = ents.add_face(hole.reverse)
						f.erase!
					}
				else
					outer_loop = @outer_loop
					curve_group  =ents.add_group
					curve_group.entities.add_curve(outer_loop)
					curve_group.explode
				end
				profile_bounds = Geom::BoundingBox.new.add(@outer_loop)
				b_table = (0..3).to_a.map{|c| profile_bounds.corner(c).to_a}
				grid = VBO::ShapeForge.align_table(b_table)
				point = grid[@placement_point.to_i - 1]
				grid.each{|pt| ents.add_cpoint(pt) if pt!= point}
				#ents.add_cpoint(point)
				ents.transform_by_vectors(ents, Geom::Vector3d.new(point.to_a).reverse)

				group = ents.add_group(face)
				#entities.transform_by_vectors(entities, [-@x_offset, - @y_offset, 0])
			end
			def get_profile_face(su_defn)
				ents = su_defn.entities
				faces = ents.grep(Sketchup::Face)
				faces.max_by{|f| f.area}
			end

			def get_valid_path(su_defn)

				valid_path_edges=nil
				ents=su_defn.entities
				edges=ents.grep(Sketchup::Edge)
				if edges.length>0
					pts_chain=Chain.new
					valid_path=pts_chain.set(edges)
				end

				if valid_path
					valid_path_edges=edges
				end

				return valid_path_edges

			end

			def load_attributes_from_defn(su_defn)

				dicts=su_defn.attribute_dictionaries
				if dicts and dicts[@dict]
					profile_properties = su_defn.get_attribute(@dict,@key,nil)
					if profile_properties
						load_from_string(profile_properties)
						self.x_scale=1.0
						self.y_scale=1.0
					end
				end

			end

			def load_from_string(string)
				if File.exist?(string)
					load_from_skp(string)
				else
					unless string.start_with?('{')
						arr = string.split(" ")
        		self.name = arr[0]
						# puts @name
						props = string.split("|extended|")
						base_props_string=props[0]

						base_props=base_props_string.to_s.split("|")
						base_props.each_index {|i|

							case i
							when 0 #the outer loop
								load_outer_loop_from_string(base_props[i])
							else
								load_hole_from_string(base_props[i])
							end

						}

						if props.length>1
							load_extended_properties_from_string(props[1])
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
						}
						# puts @outer
						@material_name = @material_name.gsub('&lt', '<')
						@outer_loop = @outer
					end
				end
			end

			def load_outer_loop_from_string(outer_loop)

				parse_points=outer_loop.split(/\s+/)
				len=parse_points.length
				num_points=((len-1).to_f/2.0).to_i
				# @name=parse_points[0]
				j=1
				while (j<len)
					p=Geom::Point3d.new(parse_points[j].to_f,parse_points[j+1].to_f,0)
					add_point(p)
					j+=2
				end

			end

			def load_hole_from_string(hole)

				hole_pts=[]
				parse_points=hole.split(/\s+/)
				len=parse_points.length
				num_points=((len).to_f/2.0).to_i
				j=0

				while (j<len)
					p=Geom::Point3d.new(parse_points[j].to_f,parse_points[j+1].to_f,0)
					hole_pts.push(p)
					j+=2
				end

				@holes.push(hole_pts)

			end

			def load_extended_properties_from_string(string)

				string=string.delete("\n")

				props=string.split("|")
				@placement_point=props[0].to_i
				@mirror=props[1]=="true" ? true : false
				@rotation=props[2].to_f
				@x_offset=props[3].to_f
				@y_offset=props[4].to_f
				@smooth_angle=props[5].to_f
				@x_scale=props[6].to_f
				@y_scale=props[7].to_f
				@dimension=props[8].to_i
				@material_name=props[9].nil? ? "Default" : props[9].gsub('&lt', '<')
				@layer_name=props[10].nil? ? Sketchup.active_model.layers[0].name : props[10]
				@junction_style=props[11].nil? ? 'continuous' : props[11]
				@extrude_mode=props[12].nil? ? 'follow_me_mode' : props[12]
			end
		end

		class Curve

			attr_reader :points

			def initialize(pts)

				self.points=pts

			end

			##
			def edges

				arr=[]
				num_edges=(@points.length/2.0).to_i
				num_edges.times {|i|
					index=i*2
					arr.push([@points[index],@points[index+1]])
				}
				return arr

			end

			##
			def first_edge

				return [@points[0],@points[1]]

			end

			##
			def last_edge

				return [@points[-2],@points[-1]]

			end
			##
			def points=(pts)

				@points=pts.collect {|p| Geom::Point3d.new(p.x,p.y,p.z)}

			end

			##
			def length

				return calc_length(@points)

			end

			##
			def calc_length(pts)

				running_length=0.0

				(pts.length-1).times {|i|
					p1=pts[i]
					p2=pts[i+1]
					vec=p1.vector_to(p2)
					running_length+=vec.length
				}

				return running_length


			end

			##
			def flattened_length

				flattened_curve_points=flatten_curve(@points)
				return calc_length(flattened_curve_points)

			end

			##

			###
			def flatten_curve(pts)

				pts=pts.collect {|p| p.clone}
				pts.each {|p| p.z=0.0}
				return pts

			end


		end

		class Chain

			include Enumerable
			include Geometry

			def initialize(pts=nil)
				raise ArgumentError,"points array not passed to chain initializer",caller unless (pts.is_a?(Array) or pts.nil?)
				@path = correct_array(pts) if pts
				@edge_trans_array=[]
				@point_trans_array=[]
			end
			def correct_array(a)
				if a.length > 2
					pts = a[0] == a[-1] ? a[0..-2].uniq + [a[0]] : a.uniq

					loop do
						point = pts.find{|c|
							i = pts.index(c)
							if ![0, pts.length - 1].include?(i)
								v1 = c.vector_to(pts[i - 1])
								v2 = c.vector_to(pts[i + 1])
								v1.length * v2.length == 0 || v1.samedirection?(v2)
							else
								if pts[0] == pts[-1]
									v1 = c.vector_to(pts[1])
									v2 = c.vector_to(pts[-2])
									v1.length * v2.length == 0 || v1.samedirection?(v2)
								else
									nil
								end
							end
						}
						if point.nil?
							break
						else
							pts.delete_at(pts.index(point))
						end
					end
					pts
				else
					a
				end
			end
			##
			def index(pt)

				return @path.index(pt)

			end

			##
			def length

				@path.length

			end
			##
			def closest_point_on_path(pickray,trans=Geom::Transformation.new)

				edges=self.edges
				distances=[]
				closest_point_on_edges=edges.collect {|edge|
					line=edge
					line=line.collect {|p| p.transform(trans)}
					closest_pts=Geom.closest_points(pickray,line)
					p0=closest_pts[0]
					p1=closest_pts[1]
					line_vec=line[0].vector_to(line[1])
					p_vec=line[0].vector_to(p1)
					if (line_vec.samedirection?(p_vec)) and (line_vec.length<=p_vec.length)
						p1.set!(line[1])
					elsif (!line_vec.samedirection?(p_vec))
						p1.set!(line[0])
					end
					#distances.push(p0.distance(p1))
					p1
				}

				distances=closest_point_on_edges.collect {|p| p.distance_to_line(pickray)}
				min_distance=distances.min
				index=distances.index(min_distance)
				closest_point=closest_point_on_edges[index]
				return closest_point, index

			end
			def closest_point_on_chain(pickray, trans = Geom::Transformation.new)
				self.edges.each_with_index.map{|edge, i|
					line = edge.map {|p| p.transform(trans)}
					closest_pts = Geom.closest_points(pickray,line)
					if point_on_edge(closest_pts[1], line)
						[i, closest_pts[1], closest_pts[1].distance(closest_pts[0])]
					else
						[i, nil, 1000000]
					end
				}.min_by{|c| c[2]}[0..1]
			end
			def closest_point_on_chain1(view, x,y, trans = Geom::Transformation.new)
				ip = view.inputpoint(x,y).position
				edge = self.edges.each_with_index{|c, i|
					line = c.map{|v| v.transform(trans)}
					pp = ip.project_to_line(line)
					point_on_edge(pp, line) ?
					[i, pp, pp.distance_to_line(line)] :
					[i, nil, 10000000000]

				}.min_by{|c| c[2]}[0..1]
			end


			def split_at_point(pickray, trans = Geom::Transformation.new)
				i, point = closest_point_on_chain(pickray, trans)
				temp_path = @path
				temp_path.insert(i + 1, point.transform(trans.inverse))
				if [0, length - 1].include?(i) && @path[0] == @path[-1]
					[]
				else
					spath1 = temp_path[0..i + 1]
					spath2 = temp_path[i + 1 ..length - 1]
					[spath1, spath2]
				end
			end
			def split_at_junction(i)
				if [0, length - 1].include?(i) && @path[0] == @path[-1]
					[]
				else
					spath1 = @path[0..i]
					spath2 = @path[i..length - 1]
					spath3 = @path[i..length - 2]
					if @path[0] == @path[-1]
						[spath3 + spath1, []]
					else
						[spath1, spath2]
					end
				end
			end
			##
			def distance_along_path(point,trans=Geom::Transformation.new)

				edges=self.edges
				running_length=0.0
				point_on_path=false

				edges.each {|edge|
					edge=edge.collect {|p| p.transform(trans)}
					dist=point_on_edge(point,edge)
					if !dist
						edge_vec=edge[0].vector_to(edge[1])
						running_length+=edge_vec.length
					else
						point_on_path=true
						running_length+=dist
						break
					end
				}
				if point_on_path
					return running_length
				else
					return nil
				end

			end

			##
			def chain_length(trans=Geom::Transformation.new)

				running_length=0.0

				(@path.length-1).times {|i|
					p1=@path[i].transform(trans)
					p2=@path[i+1].transform(trans)
					vec=p1.vector_to(p2)
					running_length+=vec.length
				}

				return running_length

			end

			##
			def point_at_distance(distance,trans=Geom::Transformation.new)

				edges=self.edges
				running_length=0.0
				edge_length=0.0
				edge_vec=nil
				delta=0.0

				edges.each {|edge|
					edge=edge.collect {|p| p.transform(trans)}
					edge_vec=edge[0].vector_to(edge[1])
					edge_length=edge_vec.length
					running_length+=edge_length
					delta=running_length-distance
					break if running_length>distance
				}

				edge_vec.length=(edge_length-delta)
				pt=edge[0].offset(edge_vec)

				return pt

			end

			##
			def edges

				num_edges=self.num_points-1
				e=[]
				num_edges.times {|i|
					p0=Geom::Point3d.new(@path[i])
					p1=Geom::Point3d.new(@path[i+1])
					e.push([p0,p1])
				}

				return e

			end

			def each

				@path.each {|p| yield(p)}

			end

			def num_points

				return @path.length

			end

			def closed_path?

				return @path.first==@path.last

			end

			def set_path(pts_array)

				@path=pts_array.dup

			end

			def path

				return @path.dup

			end

			def clear

				@path=[]

			end

			def get_edges()

				edges=[]
				num_pts=@path.length

				(num_pts-1).times {|i|
					edges.push([@path[i],@path[i+1]])
				}
				return edges

			end

			#
			def transformation_at(edge_index)
				calc_trans_array[edge_index]
			end

			##
			def point_transformation_at(point_index)
				return @point_trans_array[point_index]
			end

			#
			def angle_at(pt_index)

				return nil if pt_index==0
				return nil if pt_index==(@path.length-1)

				prev_vec=@path[pt_index-1].vector_to(@path[pt_index])
				next_vec=@path[pt_index].vector_to(@path[pt_index+1])

				return prev_vec.angle_between(next_vec)

			end

			#set the path based on an array of edges - edges should form a continuous chain
			def set(edges,first_vertex=nil)

				@path=[] if edges.length==0

				all_verts=edges.collect {|e| e.vertices}
				all_verts.flatten!

				num_verts = Hash.new(0)
				all_verts.each {|v| num_verts[v]+=1}

				#find the end points of the path and validate the path
				end_verts=[]
				valid=true
				num_verts.each_pair {|v,num|
					if num==1   #a start or end point of the path
						end_verts.push(v)
						valid=false if end_verts.length>2   #the path is not valid if there are more than two end points
					end
					if num>2  #the path is not valid
						valid=false
					end
				}
				return false if not valid

				@path=[]   #the ordered points that will make up the path
				if end_verts.length==0  #no end vertex found, so we must have a closed loop
					first_vertex=edges[0].start   #it shouldn't matter what vertex we start at so pick the start vertex of the first edge
				else
					first_vertex=first_vertex||end_verts[0]     #pick the first end vertex found and give the user the option of reversing the path later
				end

				@path.push(first_vertex.position)
				current_edge=edges.find {|edge| edge.vertices.index(first_vertex)}

				num_edges=edges.length
				current_vertex=first_vertex

				num_edges.times {|i|
					verts=current_edge.vertices
					next_vert=current_edge.other_vertex(current_vertex)
					@path.push(next_vert.position)
					current_vertex=next_vert
					vert_edges=current_vertex.edges
					vert_edges.delete_if {|e| !edges.include?(e)}  #remove any edge found that is not in the selected path of edges
					vert_edges.delete_if {|e| e==current_edge}	#delete the current edge from the set of edges - there should be only one edge left
					if vert_edges.length>1
						p "Error computing path"
						@path=[]
						return false
					elsif (vert_edges.empty?) and (i<(num_edges-1))#this is possible if there are independent edges in the selection
						return false
					end
					current_edge=vert_edges[0]
				}

				return true

			end

			#
			def add(point)

				@path.push(point)
				return self

			end

			#
			def pop()

				return @path.pop()

			end

			#
			def first

				return @path.first

			end

			#
			def last

				return @path.last

			end

			#
			def reverse!

				@path.reverse!

			end

			#
			def transform!(trans)

				@path=@path.collect {|p| p.transform(trans)}
				self

			end

			#
			def [](index)

				return @path[index]

			end

			##
			def []=(index,value)

				@path[index]=value


			end

			#
			def convert_pts_to_arrays

				return @path.collect {|p| p.to_a}

			end


			def offset!(x_distance,y_distance)

				offset_path=[]
				num_edges=@path.length-1

				#set the first offset point
				p1=@path[0]
				p2=@path[1]

				local_trans=self.transformation_at(0)
				local_x=local_trans.xaxis
				local_x.length = x_distance
				local_y=local_trans.yaxis
				local_y.length=y_distance

				offset_vec=local_x+local_y
				offset_pt=p1.offset(offset_vec)
				offset_path[0]=offset_pt
				start_offset_pt=offset_pt

				#the other offset points will depend also on the orientation of the next edge
				num_edges.times {|i|

					p1=@path[i]
					p2=@path[i+1]
					this_edge_vec=p1.vector_to(p2)

					extruded_offset_pt=start_offset_pt.offset(this_edge_vec)
					offset_path[i+1]=extruded_offset_pt

					if @path[i+2]!=nil  #make sure there is another edge after this one
						p1=@path[i+1]
						p2=@path[i+2]
						next_edge_vec=p1.vector_to(p2)

						local_trans=self.transformation_at(i+1)
						local_x=local_trans.xaxis
						local_x.length=x_distance
						local_y=local_trans.yaxis
						local_y.length=y_distance

						offset_vec=local_x+local_y
						next_offset_pt=p1.offset(offset_vec) #offset the point
						next_extruded_offset_pt=next_offset_pt.offset(next_edge_vec)

						#now calculate the corrected initially extruded point
						this_edge=[start_offset_pt,extruded_offset_pt]
						next_edge=[next_offset_pt,next_extruded_offset_pt]
						closest_pts=Geom.closest_points(this_edge,next_edge)
						if this_edge_vec.samedirection?(next_edge_vec)
							corrected_extruded_offset_pt=extruded_offset_pt
						else
							mid_point=Geom.linear_combination(0.5,closest_pts[0],0.5,closest_pts[1])
							corrected_extruded_offset_pt=mid_point
						end

						offset_path[i+1]=corrected_extruded_offset_pt  #replace the point with the corrected one
					else
						local_trans=self.transformation_at(i)
						local_x=local_trans.xaxis
						local_x.length=x_distance
						local_y=local_trans.yaxis
						local_y.length=y_distance

						offset_vec=local_x+local_y
						offset_pt=p2.offset(offset_vec)  #offset the point
						offset_path[i+1]=offset_pt
					end
					start_offset_pt=next_offset_pt
				}

				if self.closed_path?
					@path=offset_path
					equalize_first_and_last_point()
				else
					@path=offset_path
				end

			end

			#
			def equalize_first_and_last_point()

				p0=path[0]
				p1=path[1]
				first_edge_vector=p1.vector_to(p0)
				first_edge_line=[p1,first_edge_vector]

				p2=@path[-1]
				p3=@path[-2]
				last_edge_vector=p3.vector_to(p2)
				last_edge_line=[p3,last_edge_vector]

				closest_pts=Geom.closest_points(first_edge_line,last_edge_line)
				mid_point=Geom.linear_combination(0.5,closest_pts[0],0.5,closest_pts[1])

				@path[0]=mid_point
				@path[-1]=mid_point.clone

			end

			#
			def offset_global_z!(distance)

				y_offset_vec=Geom::Vector3d.new(0,0,1)
				y_offset_vec.length=distance
				y_trans=Geom::Transformation.new(y_offset_vec)
				@path = @path.collect {|p| p.transform(y_trans)}

			end #y_offset

				###
			def draw(view)

				marker_size=40
				view.line_width=6

				if self.num_points>1
					lines=self.edges()
					first_line_vec=lines[0][0].vector_to(lines[0][1])
					last_line_vec=lines[-1][1].vector_to(lines[-1][0])
					start_marker_length=[view.pixels_to_model(marker_size,lines[0][0]),lines[0][0].distance(lines[0][1])].min
					end_marker_length=[view.pixels_to_model(marker_size,lines[-1][1]),lines[-1][0].distance(lines[-1][1])].min
					chain_start=lines[0][0].clone
					chain_end=lines[-1][1].clone
					first_line_vec.length=start_marker_length
					last_line_vec.length=end_marker_length
					offset_chain_start=chain_start.offset(first_line_vec)
					offset_chain_end=chain_end.offset(last_line_vec)
					view.drawing_color=START_EDGE_COLOR
					view.draw_line(chain_start,offset_chain_start)
					view.drawing_color=END_EDGE_COLOR
					view.draw_line(offset_chain_end,chain_end)
					lines[0][0]=offset_chain_start
					lines[-1][1]=offset_chain_end
					view.drawing_color=SELECTED_EDGE_COLOR
					lines.each {|line| view.draw_line(line[0],line[1])}

				end

				#draw_all_axis(view)

			end

			##
			def draw_all_axis(view)

				edges=self.edges()
				edges.each_index {|i|
					trans=self.transformation_at(i)
					draw_axis(view,trans)
				}

			end

			##
			def draw_axis(view,trans)

				view.line_width=3
				origin=trans.origin
				dist=view.pixels_to_model(32,origin)
				x_axis=trans.xaxis
				y_axis=trans.yaxis
				z_axis=trans.zaxis
				x_axis.length=dist
				y_axis.length=dist
				z_axis.length=dist

				px=origin.offset(x_axis)
				py=origin.offset(y_axis)
				pz=origin.offset(z_axis)

				view.drawing_color="red"
				view.draw_line(origin,px)
				view.drawing_color="green"
				view.draw_line(origin,py)
				view.drawing_color="blue"
				view.draw_line(origin,pz)

			end

			def start_vector
				@path[0].vector_to(@path[1])
			end

			def end_vector
				if length > 2
					@path[-2].vector_to(@path[-1])
				else
					@path[1].vector_to(@path[0])
				end
			end

			def calc_trans_array(index = nil)

				previous_x_axis=nil
				previous_y_axis=nil
				previous_z_axis=nil

				edge_trans_array=[]
				@point_trans_array=[]
				edges=get_edges()
				index = edges.length - 1 if index.nil?
				edges.each_index {|i|
					break if i > index
					edge=edges[i]
					origin=Geom::Point3d.new(edge[0])
					end_pos=Geom::Point3d.new(edge[1])

					zaxis = origin-end_pos
					if zaxis.length==0.0
						zaxis=Geom::Vector3d.new(0,0,1)
					end

					if previous_x_axis!=nil

						y_axis=zaxis.cross(previous_x_axis)
						fix_vector!(y_axis)

						if !y_axis.valid?
							y_axis=previous_y_axis
						end

						if y_axis.samedirection?(previous_y_axis.reverse)
							y_axis=previous_y_axis.clone
						end

						x_axis=y_axis.cross(zaxis)
						fix_vector!(x_axis)
						if x_axis.samedirection?(previous_x_axis.reverse)
							x_axis=previous_x_axis.clone
							y_axis=zaxis.cross(x_axis)
							fix_vector!(y_axis)
						end

						if !zaxis.samedirection?(previous_z_axis) and !x_axis.samedirection?(previous_x_axis) and !y_axis.samedirection?(previous_y_axis)
							trans=Geom::Transformation.new(origin,zaxis) #this will keep the y axis upright for helical paths
							previous_edge_trans=edge_trans_array[i-1]
							t=Geom::Transformation.interpolate(previous_edge_trans, trans, 0.5)
							@point_trans_array[i]=Geom::Transformation.new(t.xaxis,t.yaxis,t.zaxis,origin)
							@point_trans_array[i]=trans
						else
							trans=Geom::Transformation.new(x_axis,y_axis,zaxis,origin)
						end
					else
						trans=Geom::Transformation.new(origin,zaxis)
					end

					previous_x_axis=trans.xaxis
					previous_y_axis=trans.yaxis
					previous_z_axis=trans.zaxis

					edge_trans_array.push(trans)

				}
				edge_trans_array
			end
			private


			###

			##
			def fix_vector!(vec)

				x=vec.x
				y=vec.y
				z=vec.z

				x=x.abs if x==0.0
				y=y.abs if y==0.0
				z=z.abs if z==0.0

				vec.set!(x,y,z)

			end

		end

		def self.interpolate_transformations(t1, t2, factor)
			angle = t1.xaxis.angle_between(t2.xaxis)
			rot = Geom::Transformation.rotation(t1.origin, t1.zaxis, angle * factor)
			rot * t1
		end

		module Trim

			def self.solid?(container)
			  return false unless instance?(container)

			  # definition(container).entities.find_all{|c| c.is_a?(Sketchup::Edge)}.all? { |e| e.faces.size.even? }
				container.manifold?
			end

			def self.within?(point, container, on_boundary = true, verify_solid = true)
			  return false if verify_solid && !solid?(container)

			  point = point.transform(container.transformation.inverse)

			  vector = Geom::Vector3d.new(234, 1343, 345)
			  ray = [point, vector]

			  intersections = []

			  definition(container).entities.grep(Sketchup::Face) do |face|
				return on_boundary if within_face?(point, face)

				intersection = Geom.intersect_line_plane(ray, face.plane)
				next unless intersection
				next if intersection == point

				next unless (intersection - point).samedirection?(vector)

				next unless within_face?(intersection, face)

				intersections << intersection
			  end

			  intersections = uniq_points(intersections)

			  intersections.size.odd?
			end



			def self.trim(target, modifier)
				if !target.respond_to?(:bounds) || !modifier.respond_to?(:bounds)
					Sketchup.active_model.abort_operation
					return
				end
				target_bounds = target.bounds
				modifier_bounds = modifier.bounds
				inter = target_bounds.intersect(modifier_bounds)
				if inter.empty?
					return target
				else
					return false unless solid?(target) && solid?(modifier)
					target = target.make_unique if target.is_a?(Sketchup::Group) || target.is_a?(Sketchup::ComponentInstance)
					modifier = modifier.make_unique if modifier.is_a?(Sketchup::Group)

					temp_group = target.parent.entities.add_group
					merge_into(temp_group, modifier, true)
					modifier = temp_group

					target_ents = definition(target).entities
					modifier_ents = definition(modifier).entities

					add_intersection_edges(target, modifier)

					overlapping_edges = find_corresponding_faces(target, modifier, nil)[0].flat_map(&:edges).map(&:vertices)


					erase1 = find_faces(target, modifier, true, false)
					erase2 = find_faces(modifier, target, false, false)
					c_faces1, c_faces2 = find_corresponding_faces(target, modifier, true)
					erase1.concat(c_faces1)
					erase2.concat(c_faces2)
					erase_faces_with_edges(erase1)
					erase_faces_with_edges(erase2)

					modifier_ents.each { |f| f.reverse! if f.is_a? Sketchup::Face }
					merge_into(target, modifier)

					overlapping_edges.select! { |vs| vs.all?(&:valid?) }
					overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
					target_ents.erase_entities(find_coplanar_edges(overlapping_edges))

					weld_hack(target_ents)
					reduce_solid(target_ents)
					if solid?(target)
						target
					else
						nil
					end
				end
			end

			def self.reduce_solid(entities)

				VBO::ShapeForge::FixSolid.fix_solid(entities)
				VBO::ShapeForge::FixSolid.fix_solid(entities)
				s = VBO::ShapeForge::SolidShell.new(entities)
				s.resolve
				s.internal_faces.each{|c| c.erase!}
				s.external_faces.each{|c| c.erase!}
				s.reversed_faces.each{|c| c.reverse!}
				entities.find_all{|c| c.is_a?(Sketchup::Edge)}.each{|c| c.find_faces}
				VBO::ShapeForge::FixSolid.fix_solid(entities)
			end

			def self.definition(instance)
			  instance.definition
			end

			def self.instance?(entity)
			  entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
			end

			def self.uniq_points(points)
			  points.reduce([]) { |a, p| a.any? { |p1| p1 == p } ? a : a << p }
			end

			def self.within_face?(point, face, on_boundary = true)
			  pc = face.classify_point(point)
			  return on_boundary if [Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(pc)

			  pc == Sketchup::Face::PointInside
			end

			def self.add_intersection_edges(container1, container2)
			  entities1 = definition(container1).entities
			  entities2 = definition(container2).entities

			  temp_group = container1.parent.entities.add_group

			  entities1.intersect_with(
				false,
				container1.transformation,
				temp_group.entities,
				IDENTITY,
				true,
				find_mesh_geometry(entities2)
			  )
			  entities2.intersect_with(
				false,
				container1.transformation.inverse,
				temp_group.entities,
				container1.transformation.inverse,
				true,
				find_mesh_geometry(entities1)
			  )

			  interior_hole_hack(merge_into(container1, temp_group, true).grep(Sketchup::Edge))
			  interior_hole_hack(merge_into(container2, temp_group).grep(Sketchup::Edge))

			  nil
			end

			def self.point_at_face(face)
			  return if face.area.zero?

			  index = 1
			  begin
				points = face.mesh.polygon_points_at(index)
				index += 1
			  end while points[0].on_line?(points[1], points[2])

			  Geom.linear_combination(
				0.5,
				Geom.linear_combination(0.5, points[0], 0.5, points[1]),
				0.5,
				points[2]
			  )
			end

			def self.find_faces(scope, reference, interior, on_surface)
			  definition(scope).entities.select do |f|
				next unless f.is_a?(Sketchup::Face)
				point = point_at_face(f)
				next unless point
				point.transform!(scope.transformation)
				next if interior != within?(point, reference, interior == on_surface, false)

				true
			  end
			end

			def self.find_corresponding_faces(container1, container2, orientation)
			  faces = [[], []]

			  definition(container1).entities.grep(Sketchup::Face) do |face1|
				normal1 = transform_as_normal(face1.normal, container1.transformation)
				points1 = face1.vertices.map { |v| v.position.transform(container1.transformation) }
				definition(container2).entities.grep(Sketchup::Face) do |face2|
				  next unless face2.is_a?(Sketchup::Face)
				  normal2 = transform_as_normal(face2.normal, container2.transformation)
				  next unless normal1.parallel?(normal2)
				  points2 = face2.vertices.map { |v| v.position.transform(container2.transformation) }
				  next unless points1.all? { |v| points2.include?(v) }
				  unless orientation.nil?
					next if normal1.samedirection?(normal2) != orientation
				  end

				  faces[0] << face1
				  faces[1] << face2
				end
			  end

			  faces
			end

			def self.purge_edges(entities)

			  to_purge = entities.grep(Sketchup::Edge).select { |e| e.faces.size < 2 }
			  entities.erase_entities(to_purge)

			  nil
			end

			def self.merge_into(destination, to_move, keep_original = false)
			  tr = destination.transformation.inverse * to_move.transformation
			  entities = definition(destination).entities
			  temp = entities.add_instance(definition(to_move), tr)
			  to_move.erase! unless keep_original

			  temp.explode
			end

			def self.find_coplanar_edges(entities)
			  entities.grep(Sketchup::Edge).select do |e|
				next unless e.faces.size == 2
				next unless e.faces[0].material == e.faces[1].material
				next unless e.faces[0].layer == e.faces[1].layer

				next unless e.faces[0].normal.parallel?(e.faces[1].normal)

				e.faces[0].vertices.all? do |v|
				  e.faces[1].classify_point(v.position) != Sketchup::Face::PointNotOnPlane
				end
				e.faces[1].vertices.all? do |v|
				  e.faces[0].classify_point(v.position) != Sketchup::Face::PointNotOnPlane
				end
			  end
			end

			def self.weld_hack(entities)
			  return if solid?(entities.parent)

			  temp_group = entities.add_group
			  naked_edges(entities).each do |e|
				temp_group.entities.add_line(e.start, e.end)
			  end
			  temp_group.explode

			  nil
			end

			def self.naked_edges(entities)
			  entities.grep(Sketchup::Edge).select { |e| e.faces.size == 1 }
			end

			def self.erase_faces_with_edges(faces)
			  return if faces.empty?
			  erase = faces + (faces.flat_map(&:edges).select { |e| (e.faces - faces).empty? } )
			  erase.first.parent.entities.erase_entities(erase)

			  nil
			end

			def self.find_mesh_geometry(entities)
			  entities.select { |e| [Sketchup::Face, Sketchup::Edge].include?(e.class) }
			end

			def self.transform_as_normal(normal, transformation)
			  tr = transpose(transformation).inverse

			  normal.transform(tr).normalize
			end

			def self.transpose(transformation)
			  a = transformation.to_a

			  Geom::Transformation.new([
				a[0], a[4], a[8],  0,
				a[1], a[5], a[9],  0,
				a[2], a[6], a[10], 0,
				0,    0,    0,     a[15]
			  ])
			end

			def self.interior_hole_hack(edges)
			  return if edges.empty?

			  entities = edges.first.parent.entities
			  old_entities = entities.to_a
			  edges.each(&:find_faces)
			  new_faces = entities.to_a - old_entities

			  entities.erase_entities(new_faces.select { |f| !wrapping_face(f) || f.edges.any? { |e| e.faces.size != 2 } })

			  nil
			end

			def self.wrapping_face(face)
			  (face.edges.map(&:faces).inject(:&) - [face]).first
			end


		end
	end
end
