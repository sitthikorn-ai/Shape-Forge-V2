require 'sketchup.rb'
Sketchup.require File.join(File.dirname(__FILE__), 'methods')

module VBO::ShapeForge
	class ShapeForgeEntityObserver < Sketchup::EntityObserver
		def onEraseEntity(entity)
			# puts "onEraseEntity: #{entity}"
		end
		def onChangeEntity(entity)
			# puts "onChangeEntity: #{entity}"
			pm = VBO::ShapeForge::Identify.profile_member?(entity)
			#pm.correct_transformation
		end
	end
	class Extruder
		def initialize(chain, profile, trans = Geom::Transformation.new)
			@chain = Chain.new(chain.map{|c| c.transform(trans.inverse)})
			@profile = profile
			@junctions = get_junctions_continuous
		end
		def profile_loops_at(junction)
			@junctions[junction]
		end
		def get_project_planes_continuous
			chain = @chain
			first_plane = [chain[0], chain[0].vector_to(chain[1])]
			project_planes = [first_plane]
			# calculate the project planes
			for i in 1..chain.length - 2
				v1 = chain[i].vector_to(chain[i-1])
				v2 = chain[i].vector_to(chain[i+1])
				if v1.parallel?(v2)
					normal = v2
				else
					v3 = v1 * v2
					v4 = v1.normalize + v2.normalize
					normal = v3 * v4
				end
				plane = [chain[i], normal]
				project_planes[i] = [plane]
			end
			if chain.closed_path? || chain[0] == chain[-1]
				v1 = chain[0].vector_to(chain[-2])
				v2 = chain[0].vector_to(chain[1])
				if v1.parallel?(v2)
					normal = v2
				else
					v3 = v1 * v2
					v4 = v1.normalize + v2.normalize
					normal = v3 * v4
				end
				last_plane = [chain[0], normal]
				project_planes << last_plane
				project_planes[0] = last_plane
			else
				last_plane = [chain[-1], chain[-2].vector_to(chain[-1])]
				project_planes << last_plane
			end
			project_planes
		end
		def profile_loops_at_point(pickray, trans = Geom::Transformation.new)
			chain = @chain
			closet_point = chain.closest_point_on_chain(pickray, trans)
			point = closet_point[1].transform(trans.inverse)
			index = closet_point[0]
			plane = [point, chain[index].vector_to(chain[index + 1])]
			points = []
			profile_loops_at(index)[0].zip(profile_loops_at(index + 1)[0]).each{|line|
				points << Geom.intersect_line_plane([line[0], line[0].vector_to(line[1])],plane)
			}
			points
		end
		def get_junctions_continuous
			planes = get_project_planes_continuous
			chain = @chain
			profile = @profile
			trans = Geom::Transformation.new(chain[0], chain[0].vector_to(chain[1]).reverse)
			origin = profile.loops.map{|l| profile.get_transformed_loop(l).map{|c| c.transform(trans)}}
			last = origin
			juncs = []
			# put points on planes
			for i in 0..chain.length - 1
				plane = planes[i]
				vector = i == 0 ? chain[0].vector_to(chain[1]) : chain[i - 1].vector_to(chain[i])
				this = last.map{|l| l.map{|pt|
					Geom.intersect_line_plane([pt, vector], planes[i])}
				}
				last = this
				juncs << this
			end
			if chain.closed_path?
				juncs[0] = juncs[-1]
			else
			end
			juncs
		end
		def draw_view(i, j, view, trans = Geom::Transformation.new)
			chain = @chain.path
			view.line_width = 1
			i, j = [i, j].map{|c| c < 0 ? chain.length + c : c}
			if i > j
				arr = (i..chain.length-1).to_a + (1..j).to_a
			else
				arr = (i..j).to_a
			end
			return if arr.any?{|c| chain[c].nil?}

			sections = arr.map{|c| [c, profile_loops_at(c).to_a.map{|lp| lp.map{|pt| pt.transform(trans)}}]}.to_h
			profile = @profile
			profile.is_2d? ? sections[i].each{|pt| view.draw(GL_LINE_LOOP, pt)} : sections[i].each{|pt| view.draw(GL_LINE_STRIP, pt)}

			if chain.length > 2
				arr[1..arr.length - 1].each{|index|
					sections[index-1].zip(sections[index]).each_with_index{|loops, k|
						if k == 0
							# loops[0].zip(loops[1]).each{|lp|
							# 	view.draw(GL_LINE_STRIP, lp)
							# }
							view.draw(GL_LINES, loops[0].zip(loops[1]).flatten(1))
						end
						profile.is_2d? ? view.draw(GL_LINE_LOOP, loops[1]) : view.draw(GL_LINE_STRIP, loops[1])
					}
				}
			else
				sections[i].zip(sections[j]).each_with_index{|loops, k|
					loops[0].zip(loops[1]).each{|lp|
						view.draw(GL_LINE_STRIP, lp)
					} if k == 0
				}
				profile.is_2d? ? sections[j].each{|pt| view.draw(GL_LINE_LOOP, pt)} : sections[j].each{|pt| view.draw(GL_LINE_STRIP, pt)}
			end
		end
	end
	class ForgeElement
		attr_accessor :su_defn, :group
		include Geometry


		@@dict = "ProfileBuilder"
		@@pp = 5
		@@rot = 0.0
		@@mirror = false
		@@chain = []
		@@x_offset = 0.0
		@@y_offset = 0.0
		@@smooth_angle = 45.0
		@@material_name = nil
		@@layer_name = Sketchup.active_model.layers[0].name

		def self.add(ents, chain, trans = nil)
			return if chain.length < 2
			group = ents.add_group
			pm = ForgeElement.new(group)
			trans = default_transformation(chain) if trans.nil?
			pm.transform!(trans)
			pm.set_chain(chain, trans)
			pm
		end

		def largest_area(trans = self.transformation)
			@group.definition.entities.grep(Sketchup::Face).map{|f| f.area(trans)}.max
		end

		def volume(trans = self.transformation)
			ents = @group.definition.entities
			faces = ents.find_all{|e| e.is_a?(Sketchup::Face)}
			edges = ents.find_all{|e|
				e.is_a?(Sketchup::Edge) && e.faces.length == 1
			}

			mesh_bounds = Geom::BoundingBox.new.add(
				faces.map{|f|
					f.vertices
				}.flatten.uniq.map{|v|
					v.position.transform(trans)
				}
			)
			if edges.any?
				lengths = edges.map {|edge| edge.length.to_f}
				max_length = lengths.max
				index = lengths.index(max_length)
				longest_edge = edges[index]
				p0 = longest_edge.start.position.transform(trans)
			else
				p0 = mesh_bounds.center
			end

			vol = 0.0
			faces.each {|f|
				mesh = f.mesh
				polys = mesh.polygons
				polys.each {|poly|
					p1,p2,p3 = [0,1,2].map{|i| mesh.point_at(poly[i]).transform(trans)}
					v0 = p0.vector_to(p1)
					v1 = p0.vector_to(p2)
					v2 = p0.vector_to(p3)
					vol += (v0.dot(v1.cross(v2)))/6.0
				}
			}
			bounds_vol = mesh_bounds.width*mesh_bounds.height*mesh_bounds.depth
			return [bounds_vol, vol].min
		end

		def self.default_transformation(chain)
			#if chain.length > 2
			#	trans = Geom::Transformation.new
			#elsif chain.length == 2
				# puts chain.to_s
				pm_origin = chain.first
				pm_zaxis = chain[1] - chain[0]
				trans = Geom::Transformation.new(pm_origin,pm_zaxis)
				trans = Geom::Transformation.new(trans.xaxis.reverse,trans.zaxis,trans.yaxis,pm_origin)
			#end
			#trans = Geom::Transformation.new
			return trans
		end

		# Note: default_transformation is used by PTool#draw_profile_3d in tools.rb
		# private_class_method :default_transformation
		def initialize(inst, info = false)
			#return if inst.nil?
			@group  =  inst.is_a?(Array) ? inst[0] : inst
			if @group.respond_to?(:definition)
				@group.make_unique if @group.is_a?(Sketchup::Group)
				@su_defn  =  @group.definition
				#ob = VBO::ShapeForge::ShapeForgeEntityObserver.new
				#@group.add_observer(ob)
			end
		end

		public

		def get_default_transformation(chain)
			#if chain.length > 2
			#	trans = Geom::Transformation.new
			#elsif chain.length == 2
				# puts chain.to_s
				pm_origin = chain.first
				pm_zaxis = chain[1] - chain[0]
				trans = Geom::Transformation.new(pm_origin,pm_zaxis)
				trans = Geom::Transformation.new(trans.xaxis.reverse,trans.zaxis,trans.yaxis,pm_origin)
			#end
			#trans = Geom::Transformation.new
			return trans
		end

		def reverse()
			path  =  self.chain.path
			new_path  =  path.reverse
			self.set_chain(new_path)
			start_trim = self.get_attribute("cap_0_trim")
			end_trim = self.get_attribute("cap_1_trim")
			self.set_attribute("cap_0_trim", end_trim)
			self.set_attribute("cap_1_trim", start_trim)
			self.draw()
			self.re_coordinate(transformation)
		end

		def name= (value = "")
			value = "Unnamed_Profile_##{SecureRandom.uuid[0..5]}" if value == ""
			old_name = @group.name
			@group.name = value.gsub("*_* ", " ").gsub("%20", " ")
			tprofile = self.profile
			if tprofile
				tprofile.name = value
				self.profile = tprofile
			end
			layer = self.layer
			if layer != Sketchup.active_model.layers[0] && old_name != "" && layer.name.include?(old_name)
				new_name = layer.name.gsub(old_name, value).gsub("*_* ", " ").gsub("%20", " ")
				self.layer = Sketchup.active_model.layers.add(new_name)
			end
		end


		def name
			return @group.name
		end

		def hide
			@group.hidden = true
		end


		def show

			@group.hidden = false

		end

		def definition
			return @su_defn
		end

		def <=>(other)

			return self.profile.name <=> other.profile.name

		end

		def update_profile
			profile = self.profile
			self.name = profile.name
			self.rotation = profile.rotation
			self.mirror = profile.mirror
			self.placement_point = profile.placement_point
			self.x_offset = profile.x_offset
			self.y_offset = profile.y_offset
			self.smooth_angle = profile.smooth_angle
			self.x_scale = profile.x_scale
			self.y_scale = profile.y_scale
			self.material_name = profile.material_name
			self.layer = get_layer_by_name(profile.layer_name)
			draw
		end

		def set_from_profile!(profile, redraw = true)
			profile = Shape.new(profile) if profile.is_a?(String)
			if self.profile.to_s != profile.to_s
				self.name = profile.name
				self.profile = profile
				self.rotation = profile.rotation
				self.mirror = profile.mirror
				self.placement_point = profile.placement_point
				self.x_offset = profile.x_offset
				self.y_offset = profile.y_offset
				self.smooth_angle = profile.smooth_angle
				self.x_scale = profile.x_scale
				self.y_scale = profile.y_scale
				self.material_name = profile.material_name
				self.layer = get_layer_by_name(profile.layer_name)
				self.junction_style = profile.junction_style
				self.extrude_mode = profile.extrude_mode
				draw(redraw) if redraw
			end
		end

		def instance
			return @group.is_a?(Array) ? @group[0] : @group
		end

		def instance= (g)
			@group = g.is_a?(Array) ? g[0] : g
		end

		def group_attribute(key, default = nil)
			inst = instance
			return default unless inst.respond_to?(:get_attribute)
			inst.get_attribute(@@dict, key, default)
		end

		def profile= (p)
			@su_defn.set_attribute(@@dict,'profile',p.to_s)
		end

		def entities
			inst = instance
			inst.definition.entities
		end

		def vertices
			entities.find_all{|c| c.is_a?(Sketchup::Face)}.map{|c| c.vertices}.flatten.uniq
		end

		def profile
			return if @group.to_s.include?('Delete')
			p_string = @su_defn.get_attribute(@@dict,'profile') || group_attribute('profile')
			if p_string
				return Shape.new(p_string)
			else
				return nil
			end

		end

		def material
			inst = instance
			return inst.material if inst.respond_to?(:material)
			nil
		end

		def material_name= (name)

			@su_defn.set_attribute(@@dict,'material_name',name)

		end

		def material_name

			@su_defn.get_attribute(@@dict,'material_name') || group_attribute('material_name') || @@material_name

		end

		def layer_name

			inst = instance
			if inst.respond_to?(:layer) && inst.layer
				name = inst.layer.name
			else
				name = Sketchup.active_model.layers[0].name
			end
			return name

		end

		def layer
			inst = instance
			inst.respond_to?(:layer) ? inst.layer : nil
		end

		def layer= (value)
			if value.is_a?(Sketchup::Layer)
				la = (value)
			else
				la = get_layer_by_name(value)
			end
			if la != self.layer
				inst = instance
				inst.layer = la if inst.respond_to?(:layer=)
			end
		end
		def placement_point= (pp)  #pp must be an integer between 1 and 9
			if pp != placement_point
				@su_defn.set_attribute(@@dict,'pp',pp)
				#draw
			end
		end

		def placement_point
			@su_defn.get_attribute(@@dict,'pp') || group_attribute('pp') || @@pp
		end

		def rotation= (rot)
			if rot!= rotation
				@su_defn.set_attribute(@@dict,'rotation',rot)
				#draw
			end
		end

		def rotation
			@su_defn.get_attribute(@@dict,'rotation') || group_attribute('rotation') || @@rot
		end

		def rotate!(angle)
			self.rotation += angle
		end

		def x_offset= (value)

			@su_defn.set_attribute(@@dict,'x_offset',value)

		end

		def x_offset
			@su_defn.get_attribute(@@dict,'x_offset') || group_attribute('x_offset') || @@x_offset
		end

		def y_offset= (value)
			@su_defn.set_attribute(@@dict,'y_offset',value)
		end

		def y_offset

			@su_defn.get_attribute(@@dict,'y_offset') || group_attribute('y_offset') || @@y_offset

		end

		def x_scale= (value)
			if value != x_scale
				@su_defn.set_attribute(@@dict,'x_scale',value.to_f)
				#draw
			end
		end

		def x_scale
			@su_defn.get_attribute(@@dict,'x_scale',1.0)
		end

		def y_scale= (value)
			if value != y_scale
				@su_defn.set_attribute(@@dict,'y_scale',value.to_f)
				#draw
			end
		end

		def y_scale
			@su_defn.get_attribute(@@dict,'y_scale',1.0)
		end



		def smooth_angle= (value)
			if value != smooth_angle
				@su_defn.set_attribute(@@dict,'smooth_angle',value)
				#draw
			end
		end

		def smooth_angle
			@su_defn.get_attribute(@@dict,'smooth_angle') || group_attribute('smooth_angle') || @@smooth_angle
		end


		def mirror= (value)
			if value != mirror
				@su_defn.set_attribute(@@dict,'mirror',value)
				#draw
			end
		end

		def mirror!
			self.mirror = !self.mirror
		end

		def mirror
			@su_defn.get_attribute(@@dict,'mirror') || group_attribute('mirror') || @@mirror
		end


		def set_chain(value, trans = nil)
			if value != self.chain
				trans = Geom::Transformation.new unless trans
				pts = value.collect {|p| p.transform(trans.inverse).to_a}

				@su_defn.set_attribute(@@dict,'chain', Chain.new(pts).path)
			end
		end


		def chain
			pts = @su_defn.get_attribute(@@dict,'chain') || group_attribute('chain') || @@chain
			pts = JSON.parse(pts) if pts.is_a?(String)
			pts = pts.collect {|p| Geom::Point3d.new(p)}
			Chain.new(pts)
		end

		def caps
			c = self.chain
			[
				{
					point: c[0],
					vector: c.start_vector.reverse.normalize
				},
				{
					point: c[-1],
					vector: c.end_vector.reverse.normalize
				}
			]
		end

		def closed_path?
			path = self.chain
			return path.first == path.last
		end

		def length(trans = Geom::Transformation.new)

			chain = VBO::ShapeForge::Chain.new(self.chain.path.map{|c| c.transform(self.transformation)})
			chain.offset! self.profile.x_offset, self.profile.y_offset
			total = 0
			for i in 1..chain.length - 1
			total += chain[i-1].distance(chain[i])
			end
			total
		end

		def surface_area
			area = 0.0
			faces = self.entities.grep(Sketchup::Face)
			faces.each {|f| area += f.area}
			return area
		end

		def volume(transformation = Geom::Transformation.new)
			volume = @group.volume
			if volume<0.0
				area = self.profile.area(transformation)
				volume = area * self.length(transformation)
			end
			return volume
		end

		def num_segments
			return self.chain.length - 1
		end

		def move!(pt,vec)
			trans = Geom::Transformation.new(pt)
			@group.transformation = trans
		end

		def transform!(trans)
			@group.transformation = trans unless @group.nil?
		end

		def transform_to_origin(chain)
			tr = get_default_transformation(chain)
			@group.entities.transform_entities(tr, @group.entities.to_a)
			@group.transform!(tr.inverse)
		end

		def split(p1,p2)
			p1 = Geom::Point3d.new(p1)
			p2 = Geom::Point3d.new(p2)
			new_chain = Chain.new
			trans = self.transformation
			new_chain.set_path([p1.transform(trans),p2.transform(trans)])
			entities = Sketchup.active_model.active_entities
			pm = ForgeElement.add(entities,new_chain.path)
			pm.name = self.instance.name
			copy_attributes_to(pm.instance)
			pm.set_chain(new_chain,pm.transformation)
			pm.draw()
		end

		def split_at_point(pickray, type, trans = Geom::Transformation.new)
			closet_point = self.chain.closest_point_on_chain(pickray, trans)
			point = closet_point[1].transform(trans.inverse)
			index = closet_point[0] + 1
			chain_path = self.chain.path
			chain_path.insert(index, point)
			self.set_chain(chain_path)
			split_at_junction(index, type, trans)
		end



		def split_at_junction(i, type, trans = Geom::Transformation.new)
			paths = self.chain.split_at_junction(i)
			plane = self.trim_plane_at(i)
			plane = plane[0] if plane.length == 1

			new_chain = Chain.new
			new_chain.set_path paths[1].map{|c| c.transform(trans * self.transformation)}
			entities = self.instance.parent.entities
			pm = ForgeElement.add(entities,new_chain.path)
			pm.name = self.instance.name
			copy_attributes_to(pm.instance)
			case type
			when "normal"
				set_chain(paths[0])
				pm.set_chain(new_chain, pm.transformation)
			when "miter joint"
				set_chain(paths[0])
				set_attribute("cap_1_trim",["plane", self.chain[-1], plane])
				pm.set_chain(new_chain, pm.transformation)
				pm.set_attribute("cap_0_trim",["plane", pm.chain[0], [pm.chain[0], plane[1].transform(pm.transformation.inverse * trans * self.transformation)]])

				cap_1_trim = pm.get_attribute("cap_1_trim")
				if cap_1_trim
					case cap_1_trim[0]
					when 'plane'
						type, cap, plane = cap_1_trim
						plane = plane[0] if plane.length == 1
						set_attribute(
							"cap_1_trim",
							[
								type,
								pm.chain[1],
								[
									pm.chain[1],
									plane[1].transform(pm.transformation.inverse)
								]
							]
						)
					when 'solid'
						type, cap, solid = cap_1_trim
						set_attribute(
							type,
							[
								type,
								pm.chain[1],
								solid
							]
						)
					end
				end
			when "butt joint"

			end
			self.draw
			pm.draw()
			pm.re_coordinate(trans.inverse * pm.transformation)
			[self, pm]
		end

		def correct_transformation
			value = self.chain
			set_chain(value, transformation.inverse)
			draw
			instance.transform!(transformation.inverse)
		end
		def profile_loops_at_junctions
			junctions = self.get_attribute("junctions")
			junctions = get_junctions_continuous if junctions.nil?
			{
				outer_loops: junctions[0],
				holes: junctions - [junctions[0]]
			}
		end

		def junctions
			jun = self.get_attribute("junctions")
			jun = get_junctions_continuous if jun.nil?
			jun
		end

		def edge_on_junctions?(edge)
			j = junctions
			j.any?{|lo|
				lo.include?(edge[0]) && lo.include?(edge[1])
			}
		end

		def get_project_planes_continuous
			chain = self.chain
			if chain.closed_path? || chain[0] == chain[-1]
				self.delete_attribute("cap_0_trim")
				self.delete_attribute("cap_1_trim")
			end
			s_trim_plane = self.get_attribute("cap_0_trim")
			s_trim_plane = s_trim_plane && s_trim_plane[0] == "plane" ? s_trim_plane[2] : nil
			e_trim_plane = self.get_attribute("cap_1_trim")
			e_trim_plane = e_trim_plane && e_trim_plane[0] == "plane" ? e_trim_plane[2] : nil
			if s_trim_plane
				line = [chain[0], chain[0].vector_to(chain[1])]
				intersect = Geom.intersect_line_plane(line, s_trim_plane)
				self.delete_attribute("cap_0_trim") unless intersect
				first_plane = intersect.nil? ? [chain[0], chain[0].vector_to(chain[1])] : s_trim_plane
			else
				first_plane = [chain[0], chain[0].vector_to(chain[1])]
			end
			project_planes = [first_plane]
			# calculate the project planes
			for i in 1..chain.length - 2
				v1 = chain[i].vector_to(chain[i-1])
				v2 = chain[i].vector_to(chain[i+1])
				if v1.parallel?(v2)
					normal = v2
				else
					v3 = v1 * v2
					v4 = v1.normalize + v2.normalize
					normal = v3 * v4
				end
				plane = [chain[i], normal]
				project_planes[i] = [plane]
			end
			if chain.closed_path? || chain[0] == chain[-1]
				v1 = chain[0].vector_to(chain[-2])
				v2 = chain[0].vector_to(chain[1])
				if v1.parallel?(v2)
					normal = v2
				else
					v3 = v1 * v2
					v4 = v1.normalize + v2.normalize
					normal = v3 * v4
				end
				last_plane = [chain[0], normal]
				project_planes << last_plane
				project_planes[0] = last_plane
			else
				if e_trim_plane
					line = [chain[-1], chain[-2].vector_to(chain[-1])]
					intersect = Geom.intersect_line_plane(line, e_trim_plane)
					self.delete_attribute("cap_1_trim") unless intersect
					last_plane = intersect.nil? ? [chain[-1], chain[-2].vector_to(chain[-1])] : e_trim_plane
				else
					last_plane = [chain[-1], chain[-2].vector_to(chain[-1])]
				end
				project_planes << last_plane
			end
			self.set_attribute('projected_planes', project_planes)
			project_planes
		end

		def get_junctions_continuous
			planes = get_project_planes_continuous
			profile = self.profile
			trans = Geom::Transformation.new(chain[0], chain[0].vector_to(chain[1]).reverse)
			origin = profile.loops.map{|l| profile.get_transformed_loop(l).map{|c| c.transform(trans)}}
			last = origin
			chain = self.chain
			juncs = []
			# put points on planes
			for i in 0..chain.length - 1
				plane = planes[i]
				vector = i == 0 ? chain[0].vector_to(chain[1]) : chain[i - 1].vector_to(chain[i])
				this = last.map{|l|
					l.map{|pt|
						Geom.intersect_line_plane([pt, vector], planes[i])
					}
				}
				# ap planes[i]
				# ap this
				if !this.any?{|c| c.nil?}
					last = this
					juncs << this
				end
			end
			if chain.closed_path?
				juncs[0] = juncs[-1]
				# juncs << juncs[0]
			else
			end
			self.set_attribute("junctions", juncs)
			juncs
		end

		def profile_points_at_junctions
			junctions = self.get_attribute("junctions")
			junctions = get_junctions_continuous if junctions.nil?
			junctions.flatten(1)
		end

		def profile_loops_at(junction)
			junctions = self.get_attribute("junctions")
			junctions = get_junctions_continuous if junctions.nil?
			junctions[junction]
		end

		def profile_points_at(junction)
			junctions = self.get_attribute("junctions")
			junctions = get_junctions_continuous if junctions.nil?
			junctions[junction].flatten(1).map{|c| c.to_a}
		end
		def trim_plane_at(junction)
			planes = get_project_planes_continuous
			planes[junction]
		end
		def cap_loops(cap)
			profile_loops_at(cap * (self.chain.length - 1))
		end

		def cap_points(cap)
			profile_points_at(cap * (self.chain.length - 1))
		end

		def extrude_mode
			profile.extrude_mode
		end
		def extrude_mode=(val)
			prof = self.profile
			prof.extrude_mode = val
			self.profile = prof
		end

		def junction_style
			profile.junction_style
		end
		def junction_style=(val)
			prof = self.profile
			prof.junction_style = val
			self.profile = prof
		end


		def draw(split_type = self.profile.junction_style)
			# UI.messagebox split_type
			unless [
				"continuous",
				"normal",
				"miter_joint",
				"butt_joint"
			].include?(split_type)
				split_type = "continuous"
			end
			# UI.messagebox split_type
			self.entities.clear!
			gc = create_geo(split_type)
			if split_type == "continuous"
				soften_edges
			end
			self.instance = gc
			@su_defn = instance.definition if instance.respond_to?(:definition)
			instance
		end

		def draw_view(i, j, view, trans = self.transformation)
			chain = self.chain.path
			view.line_width = 2
			i, j = [i, j].map{|c| c < 0 ? chain.length + c : c}
			if i > j
				arr = (i..chain.length-1).to_a + (1..j).to_a
			else
				arr = (i..j).to_a
			end
			sections = arr.map{|c| [c, profile_loops_at(c).map{|lp| lp.map{|pt| pt.transform(trans)}}]}.to_h
			profile = self.profile
			profile.is_2d? ? sections[i].each{|pt| view.draw(GL_LINE_LOOP, pt)} : sections[i].each{|pt| view.draw(GL_LINE_STRIP, pt)}

			if chain.length > 2
				arr[1..arr.length - 1].each{|index|
					sections[index-1].zip(sections[index]).each_with_index{|loops, k|
						loops[0].zip(loops[1]).each{|lp|
							view.draw(GL_LINE_STRIP, lp)
						} if k == 0
						profile.is_2d? ? view.draw(GL_LINE_LOOP, loops[1]) : view.draw(GL_LINE_STRIP, loops[1])
					}
				}
			else
				sections[i].zip(sections[j]).each_with_index{|loops, k|
					loops[0].zip(loops[1]).each{|lp|
						view.draw(GL_LINE_STRIP, lp)
					} if k == 0
				}
				profile.is_2d? ? sections[j].each{|pt| view.draw(GL_LINE_LOOP, pt)} : sections[j].each{|pt| view.draw(GL_LINE_STRIP, pt)}
			end
		end

		def material
			self.material_name.nil? ? nil : Sketchup.active_model.materials[self.material_name]
		end

		def draw_junction_face(ents, junction)
			outer_loop = junction[0]
			holes = junction - [outer_loop]
			face = ents.add_face(outer_loop)
			face.material = self.get_material
			holes.each{|hole|
				f = ents.add_face(hole.reverse)
				f.erase!
			}
			face
		end

		def build_junction_face(builder, junction)
			outer_loop = junction[0]
			holes = junction - [outer_loop]
			face = builder.add_face(outer_loop)
			face.material = self.get_material
			holes.each{|hole|
				f = builder.add_face(hole.reverse)
				f.erase!
			}
			builder
		end

		def update_trim(trans = Geom::Transformation.new)
			(0..1).to_a.each{|c|
				type, cap, trimmer  = self.get_attribute("cap_#{c}_trim")
				if !cap.nil?
						case type
						when "plane"
								self.trim_to_plane(trimmer, c, trans) if cap == self.chain[ - c].to_a
						when "solid"
								ins = Sketchup.active_model.find_entity_by_persistent_id trimmer
								if ins.nil?
										UI.messagebox "Cap's trimmer has changed or deleted!\nReset Cap ##{c} to default"
										self.delete_attribute("cap_#{c}_trim")
								else
										self.trim_to(ins, c, VBO::ShapeForge.collect_all_active_instances(self.definition)[0] , trimmer)# if self.instance.parent == ins.parent
								end
						end
				end
			}
		end

		def re_coordinate(transformation = Geom::Transformation.new, trans = nil )
			#if caps.map{|ca| ca.values}.any?{|c| c[0] == ORIGIN}
			#else
				#Sketchup.active_model.start_operation("re_coordinate", true)
				trans = get_default_transformation(self.chain) unless trans
				self.transform!(transformation * trans)
				@su_defn.entities.transform_entities(trans.inverse, @su_defn.entities.to_a)
				chain = self.chain
				set_chain(chain.path.map{|c| c.transform(trans.inverse)})

				# Update stored junction points to match new local coordinate space
				junctions = self.get_attribute("junctions")
				if junctions
					junctions = junctions.map{|js| js.map{|l| l.map{|pt| pt.transform(trans.inverse)}}}
					self.set_attribute("junctions", junctions)
				end

				#Sketchup.active_model.commit_operation

				cap_0_trim = get_attribute("cap_0_trim")

				if cap_0_trim
					case cap_0_trim[0]
					when 'plane'
						type, cap, plane = cap_0_trim
						#UI.messagebox plane
						plane = plane[0] if plane.length == 1
						set_attribute(
							"cap_0_trim",
							[
								type,
								self.chain[0],
								[
									self.chain[0],
									plane[1].transform(transformation.inverse * trans.inverse)
								]
							]
						)
					when 'solid'
						type, cap, solid = cap_0_trim
						set_attribute(
							type,
							[
								type,
								self.chain[0],
								solid
							]
						)
					end
				end

				cap_1_trim = get_attribute("cap_1_trim")
				if cap_1_trim
					case cap_1_trim[0]
					when 'plane'
						type, cap, plane = cap_1_trim
						plane = plane[0] if plane.length == 1
						set_attribute(
							"cap_1_trim",
							[
								type,
								self.chain[1],
								[
									self.chain[1],
									plane[1].transform(transformation.inverse * trans.inverse)
								]
							]
						)
					when 'solid'
						type, cap, solid = cap_1_trim
						set_attribute(
							type,
							[
								type,
								self.chain[1],
								solid
							]
						)
					end
				end
				#draw
				#UI.messagebox "hehe"
			self.instance
			#end
		end


		def split_edges(edges)
			# Tìm các cạnh cần xẻ là cạnh bị chứa (chứa 1 phần) bởi một cạnh khác
			overlapping = []
			until edges.empty?
				edge = edges.shift

				e = edges.find { |e| edge_overlapping_edge?(e, edge) }
				overlapping << edge if e
			end
			# puts "overlapse: #{overlapping}"
			overlapping.each do |e|
				next unless e.valid?

				es = e.parent.entities
				gr = es.add_group
				gr.entities.add_line(e.vertices.map(&:position))
				es = gr.explode

			end

			!overlapping.empty?
		end

		# edge0 đè lên edge1 khi có 1 điểm của edge1 nằm giữa egde0
		def edge_overlapping_edge?(edge0, edge1)
			line0 = edge0.vertices.map(&:position)
			line1 = edge1.vertices.map(&:position)
			v0 = line0[0].vector_to(line0[1])
			v1 = line1[0].vector_to(line1[1])
			return unless v0.parallel?(v1)
			return unless line0[0].on_line?(line1)

			line1.any? { |pt| point_between?(line0[0], line0[1], pt, false) }
		end

		def point_between?(a, b, c, at_vertex = true)
			v1 = c.vector_to(a)
			v2 = c.vector_to(b)

			if !v1.valid? || !v2.valid?
				if at_vertex
					return true
				else
					return false
				end
			end

			!v1.samedirection?(v2)
		end
		def add_face_to_polygon(pol, loops)

			triangles = Geom.tesselate(loops[0], *loops[1..-1]).each_slice(3).to_a.delete_if{|po| po[0].on_line?([po[1], po[1].vector_to(po[2])])}
			triangles.each{|tri|
				pol.add_polygon(tri)
			}
			pol
		end

		def add_face_to_builder(builder, loops)
			f = builder.add_face(loops[0], holes: loops[1..-1])
			# f.material = self.get_material
			true
		end
		#using polygon mesh
		def create_geo(split_type)

			@group.make_unique if @group.is_a?(Sketchup::Group)
			case split_type
			when 'normal'
				make_group = true
				trans = @group.transformation
			when 'continuous'
				make_group = false
				trans = Geom::Transformation.new
			when 'miter_joint', 'butt_joint'
				make_group = true
				trans = @group.transformation
			else
				return
			end

			junctions = get_junctions_continuous.map{|js| js.map{|l| l.map{|pt| pt.transform(trans)}}}
			last = junctions[0]

			planes = self.get_attribute("projected_planes")
			planes = get_projected_planes if planes.nil?
			gcs = []
			po = Geom::PolygonMesh.new

			junctions.each_with_index{|this, i|
				next if i == 0
				if make_group
					this_copy = this.clone
					last_copy = last.clone

					sub_po = Geom::PolygonMesh.new

					sub_chain = Chain.new
					sub_chain.set_path([chain[i-1], chain[i]].map{|c| c.transform(trans)})
					sub_vector = sub_chain[0].vector_to(sub_chain[1])

					case split_type
					when 'miter_joint'
					when 'butt_joint'
						if i > 1
							v1 = chain[i - 2].vector_to(chain[i - 1])
							v2 = v1 * sub_vector
							last_plane_normal = v1 * v2
							last_plane_normal = sub_vector if last_plane_normal.length == 0
						else
							last_plane_normal = sub_vector
						end
						if i < chain.length - 1
							v1 = chain[i].vector_to(chain[i + 1])
							v2 = v1 * sub_vector
							next_plane_normal = v1 * v2
							next_plane_normal = sub_vector if next_plane_normal.length == 0
						else
							next_plane_normal = sub_vector.reverse
						end

						nearest_last = last_copy.flatten.min_by{|pt|
							pt.distance(sub_chain[-1])
						}
						start_plane = [nearest_last, last_plane_normal]
						last_copy = last_copy.map{|c|
							c.map{|pt|
								 Geom.intersect_line_plane([pt, sub_vector], start_plane)
							}
						}
						sub_chain[0] = Geom.intersect_line_plane(
							[
								sub_chain[0],
								sub_vector
							],
							start_plane
						)

						farthest_this = this_copy.flatten.max_by{|pt| pt.distance(sub_chain[0])}
						end_plane = [farthest_this, next_plane_normal]
						this_copy = this_copy.map{|c| c.map{|pt| Geom.intersect_line_plane([pt, sub_vector], end_plane)}}
						sub_chain[-1] = Geom.intersect_line_plane([sub_chain[-1], sub_vector], end_plane)
					when 'normal'
						start_plane = [sub_chain[0], sub_vector]
						last_copy = last_copy.map{|c| c.map{|pt| pt.project_to_plane(start_plane)}}
						end_plane = [sub_chain[-1], sub_vector.reverse]
						this_copy = this_copy.map{|c| c.map{|pt| pt.project_to_plane(end_plane)}}
					end
					g = @group.parent.entities.add_group
					gcs << g
					ent = g.entities

					if self.profile.is_2d?
						sub_po = add_face_to_polygon(sub_po, this_copy.map{|c| c.reverse})
						sub_po = add_face_to_polygon(sub_po, last_copy)
					end
					pm = ForgeElement.add(self.entities, sub_chain.path)
					pm.instance = g
					pm.su_defn = g.definition
					copy_attributes_to(g)
					pm.set_chain(sub_chain)
					soften(self.smooth_angle, ent)

					prof = self.profile.clone
					rot = prof.rotation
					# puts "rot: #{rot}"

					prof.rotation = rot - get_rotate_angle(
						junctions[1][0].map{|c|
							c.project_to_plane(
								[
									chain[0],
									chain[0].vector_to(chain[1])
								].map{|c|
									c.transform(trans)
								}
							)
						},
						this_copy[0].map{|c|
							c.project_to_plane(
								[
									sub_chain[0],
									sub_vector
								]
							)
						}
					)
					# puts "prof.rotation: #{prof.rotation}"
					pm.profile = prof
					pm.set_from_profile!(prof, false)

					gcs << g

					this_copy.each_with_index{|this_loop, j|
						slicing(last_copy[j]).zip(slicing(this_loop)).each{|e|
							p0= e[0][0]
							p1= e[1][0]
							p2= e[1][1]
							p3= e[0][1]
							plane = Geom.fit_plane_to_points([p0, p1, p2])
							if p3.on_plane?(plane)
								sub_po.add_polygon(e[0].reverse + e[1])
							else
								sub_po.add_polygon([p0, p1, p2])
								sub_po.add_polygon([p0, p2, p3])
							end
						}
					}
					g.entities.add_faces_from_mesh(sub_po)


					edges = g.entities.find_all{|e|
						e.is_a?(Sketchup::Edge)
					}
					split = split_edges(edges)
					if split
						remove_edges = g.entities.find_all{|c|
							c.is_a?(Sketchup::Edge) &&
							c.faces.length > 2
						}
						g.entities.erase_entities(remove_edges)
					end


						edges = g.entities.find_all{|e|
							e.is_a?(Sketchup::Edge)
						}
						remove_edges = edges.find_all{|e|
							e.is_a?(Sketchup::Edge) &&
							e.faces.length == 2 &&
							e.faces[0].normal.samedirection?(e.faces[1].normal)
						}

						g.entities.erase_entities(remove_edges)

					g.material = self.get_material
					g.name = self.profile.name.gsub('*_*', ' ').gsub("%20", " ")
					pm.clear_stray_edges()

					case split_type
					when 'miter_joint'
						pm.set_attribute(
							"cap_0_trim",
							[
								"plane",
								pm.chain[0],
								[
									pm.chain[0],
									planes[i-1].flatten(1)[1].transform(trans)
								]
							]
						)
						pm.set_attribute(
							"cap_1_trim",
							[
								"plane",
								pm.chain[1],
								[
									pm.chain[1],
									planes[i].flatten(1)[1].transform(trans)
								]
							]
						)
						pm.re_coordinate
					else
						pm.re_coordinate
					end
					pm.soften_edges()
				else
					ent = self.entities
					this.each_with_index{|this_loop, j|
						slicing(last[j]).zip(slicing(this_loop)).each{|e|
							p0= e[0][0]
							p1= e[1][0]
							p2= e[1][1]
							p3= e[0][1]
							plane = Geom.fit_plane_to_points([p0, p1, p2])
							if p3.on_plane?(plane)
								po.add_polygon(e[0].reverse + e[1])
							else
								po.add_polygon([p0, p1, p2])
								po.add_polygon([p0, p2, p3])
							end
						}
					}
				end
				last = this
			}
			# @group.material = self.get_material
			unless make_group
				if  !self.chain.closed_path? && self.profile.is_2d?
					@group.entities.build{|builder|
						builder.add_face(junctions[0][0], holes: junctions[0][1..-1])

						f = builder.add_face(junctions[chain.length - 1][0], holes: junctions[chain.length - 1][1..-1])
						f.reverse!
					}
				end
				self.entities.add_faces_from_mesh(po)


				if self.extrude_mode != "normal_mode"
					edges = self.entities.find_all{|e|
						e.is_a?(Sketchup::Edge)
					}
					remove_edges = edges.find_all{|e|
						e.is_a?(Sketchup::Edge) &&
						e.faces.length == 2 &&
						e.faces[0].normal.samedirection?(e.faces[1].normal)
					}
					self.entities.erase_entities(remove_edges)
				end

				@group.name = self.profile.name.gsub('*_*', ' ').gsub("%20", " ")
				# puts "set mat"
				@group.material = self.get_material
				@group
			else
				@group.erase!
				gcs
			end
		end
		# using entities builder
		def create_geo1(split_type = @profile.junction_style)

			@group.make_unique if @group.is_a?(Sketchup::Group)
			case split_type
			when 'normal'
				make_group = true
				trans = @group.transformation
			when 'continuous'
				make_group = false
				trans = Geom::Transformation.new
			when 'miter_joint', 'butt_joint'
				make_group = true
				trans = @group.transformation
			end

			junctions = get_junctions_continuous.map{|js| js.map{|l| l.map{|pt| pt.transform(trans)}}}
			last = junctions[0]

			planes = self.get_attribute("projected_planes")
			planes = get_projected_planes if planes.nil?
			gcs = []

			unless make_group
				ent = @group.entities
				ent.build{|builder|
					junctions.each_with_index{|this, i|
						next if i == 0
						this.each_with_index{|this_loop, j|
							slicing(last[j]).zip(slicing(this_loop)).each{|e|
								p0= e[0][0]
								p1= e[1][0]
								p2= e[1][1]
								p3= e[0][1]

								plane = Geom.fit_plane_to_points([p0, p1, p2])
								if p3.on_plane?(plane)
									builder.add_face(e[0].reverse + e[1])
								else
									builder.add_face([p0, p1, p2]) if [p0, p1, p2].uniq{|c| c.to_a}.length == 3
									builder.add_face([p0, p2, p3]) if [p0, p2, p3].uniq{|c| c.to_a}.length == 3
								end
							}
						}
						last = this
					}
					if  !self.chain.closed_path? && self.profile.is_2d?
						builder.add_face(junctions[0][0], holes: junctions[0][1..-1])
						f = builder.add_face(junctions[chain.length - 1][0], holes: junctions[chain.length - 1][1..-1])
						f.reverse!
					end
					remove_edges = []
					edges = builder.entities.each{|e|
						mat = self.get_material
						if e.is_a?(Sketchup::Edge) && e.faces.length == 2
							an = e.faces[0].normal.angle_between(e.faces[1].normal)
							if an.radians % 180 == 0
								remove_edges << e
							elsif an <= self.smooth_angle.degrees
								e.soft = true
								e.smooth = true
							else

							end
						elsif e.is_a?(Sketchup::Face)
							e.material = mat
						end
					}
					builder.entities.erase_entities remove_edges
				}
				@group.name = self.profile.name.gsub('*_*', ' ').gsub("%20", " ")
				@group
			else
				junctions.each_with_index{|this, i|
					next if i == 0
					if make_group
						sub_chain = Chain.new
						sub_chain.set_path([chain[i-1], chain[i]].map{|c| c.transform(trans)})

						g = @group.parent.entities.add_group
						gcs << g
						ent = g.entities
						ent.build{|builder|
							if self.profile.is_2d?
								f = builder.add_face(this[0], holes: this[1..-1])
								f.reverse!
								builder.add_face(last[0], holes: last[1..-1])
							end
						}
						pm = ForgeElement.add(@group.entities, sub_chain.path)
						pm.instance = g
						pm.su_defn = g.definition
						copy_attributes_to(g)
						pm.set_chain(sub_chain)

						pm.profile = self.profile
						pm.set_from_profile!(profile, false)
						gcs << g
						pm.entities.build{|builder|
							this.each_with_index{|this_loop, j|
								slicing(last[j]).zip(slicing(this_loop)).each{|e|
									p0= e[0][0]
									p1= e[1][0]
									p2= e[1][1]
									p3= e[0][1]
									plane = Geom.fit_plane_to_points([p0, p1, p2])
									if p3.on_plane?(plane)
										builder.add_face(e[0].reverse + e[1]).material = self.get_material
									else
										builder.add_face([p0, p1, p2]).material = self.get_material
										builder.add_face([p0, p2, p3]).material = self.get_material
									end
								}
							}
						}
						#pm.clear_stray_edges()
						pm.soften_edges()

						pm.set_attribute(
							"cap_0_trim",
							[
								"plane",
								pm.chain[0],
								[
									pm.chain[0],
									planes[i-1].flatten(1)[1].transform(trans)
								]
							]
						)
						pm.set_attribute(
							"cap_1_trim",
							[
								"plane",
								pm.chain[1],
								[
									pm.chain[1],
									planes[i].flatten(1)[1].transform(trans)
								]
							]
						)

						pm.re_coordinate
					else
						ent = @group.entities
						ent.build{|builder|
							this.each_with_index{|this_loop, j|
								slicing(last[j]).zip(slicing(this_loop)).each{|e|
									p0= e[0][0]
									p1= e[1][0]
									p2= e[1][1]
									p3= e[0][1]
									plane = Geom.fit_plane_to_points([p0, p1, p2])
									if p3.on_plane?(plane)
											builder.add_face(e[0].reverse + e[1]).material = self.get_material
									else
											builder.add_face([p0, p1, p2]).material = self.get_material
											builder.add_face([p0, p2, p3]).material = self.get_material
									end
								}
							}
						}
					end
					last = this
				}
				@group.erase!
				gcs
			end
		end



		def slicing(a)
			b = []
			for i in 0..a.length-1
				if i == a.length - 1
					if self.profile.is_2d?
						b << [a[i], a[0]]
					else
						next
					end
				else
					b << [a[i], a[i+1]]
				end
			end
			b
		end
		def clear_stray_edges()

			ents = self.entities
			edges = ents.grep(Sketchup::Edge)
			strays = edges.find_all {|edge| edge.faces.length == 0}
			ents.erase_entities(strays)

		end

			###
		def draw_path()

			clear_existing_edges()
			chain = self.chain
			ents = self.entities
			edit_trans = Sketchup.active_model.edit_transform
			edges = []
			chain.edges.each {|edge|
				p0 = edge[0].transform(edit_trans)
				p1 = edge[1].transform(edit_trans)
				edges.push(ents.add_line([p0,p1]))
			}

			return edges

		end


		def draw_path_group(trans)

			pts = self.chain.path

			group = Sketchup.active_model.active_entities.add_group
			group_ents = group.entities
			group.transform! trans

			group_ents.add_edges(pts)
			return group

		end


		def pmpi(trans)

			@group.hidden = true
			@group.set_attribute('PMPI','pmpi_hidden',true)
			path = self.draw_path_group(trans)
			path.set_attribute('PMPI','pmpi_path',true)

		end

		def soften_edges()
			soften(self.smooth_angle)
			# puts "ents: #{entities.find_all{|e| e.is_a?(Sketchup::Face)}.map{|f|
			# 	[
			# 		f,
			# 		f.vertices.map{|v|
			# 				self.junctions.flatten(1).find{|c|
			# 					c.map{|pt|
			# 						pt.to_a.map{|c| c.round(3)}
			# 					}.include?(v.position.to_a.map{|c| c.round(3)})}
			# 		}.uniq
			# 	]
			# }.to_h
			# }"
		end

		def set_material()
			@group.material = get_material()
		end


		def get_cap_face(start)
			points = start ? cap_loops(0)[0] : cap_loops(1)[0]
			entities.find{|c| c.is_a?(Sketchup::Face) && c.outer_loop.vertices.map{|v| v.position.to_a.map{|c| c.round(3)}} - points.map{|c| c.to_a.map{|x| x.round(3)}} == []}
		end

		def profile_area
			profile = self.profile
			t = transform_by_size(profile.width,profile.height,self.x_scale,self.y_scale)
			area = profile.area(t)
			return area
		end

		def transformation
			inst = instance
			inst.respond_to?(:transformation) ? inst.transformation : Geom::Transformation.new
		end

		def xscale
				((Geom::Vector3d.new 1,0,0).transform self.transformation).length
		end

		def yscale
				((Geom::Vector3d.new 0,1,0).transform self.transformation).length
		end

		def zscale
				((Geom::Vector3d.new 0,0,1).transform self.transformation).length
		end

		def to_path(trans = Geom::Transformation.new)
			tr = self.transformation
			group_ents = self.entities
			edges = group_ents.find_all {|e| e.class == Sketchup::Edge}
			group_ents.erase_entities(edges)
			pts = self.chain.path
			pts = pts.map{|c| c.transform(trans)}
			self.set_chain(pts)
			group_ents.add_edges(pts)
			tr
		end

		def trim_to(path, cap_index, target_path, pid)
			if path.is_a?(Array)
				ins = path[-1].respond_to?(:definition) ? path[-1] : path[-2]
			elsif path.respond_to?(:definition)
				ins = path
				target_trans = target_path.nil? ? Geom::Transformation.new : Sketchup::InstancePath.new(target_path.to_a).transformation
			else
				return
			end
			# puts "trim to #{ins}"

			self.set_attribute("cap_#{cap_index}_trim", ["solid", self.chain[- cap_index].to_a,  pid])
			ins = validate_for_trim(ins)
			prepare_end_for_trim(ins, cap_index, target_trans)
			result = perform_boolean_trim(ins)
			if !result.nil?
				delete_waste(result)
			else
				return
			end
			#result
		end

		def project_to_mesh(mesh, cap_indecies)
			trans = Sketchup::InstancePath.new(mesh).transformation
			faces = mesh[-1].definition.entities.find_all{|f|
				f.is_a?(Sketchup::Face)
			}
			# puts "faces: #{faces}"
			juncs = self.junctions.map{|c| c.flatten.map{|e| e.transform(self.transformation)}}
			# ap juncs
			# puts "juncs: #{juncs}"
			rays = self.caps.map{|c|
				c.values.map{|c|
					c.transform(self.transformation)
				}
			}
			# puts "rays: #{rays}"
			cap_stretch = cap_indecies.map{|i|
				js = case i
				when 0
					juncs[1]
				when 1
					juncs[-2]
				end
				js.flatten.map{|j|
					ray = [j, rays[i][1]]
					intersect = faces.map{|f|
						# puts f
						vert = f.vertices[0].position.transform(trans)
						normal = f.normal.transform(trans)
						# puts "normal: #{[vert, normal]}"
						# puts "ray: #{ray}"
						inter = Geom.intersect_line_plane(
							ray,
							[
								vert,
								normal
							]
						)
						inter = Geom.intersect_line_plane(
							[ray[0], ray[1].reverse],
							[
								vert,
								normal
							]
						) if !inter
						# puts "inter: #{[inter.transform(trans.inverse]}"
						if inter &&
							ray[0].distance(inter) > 0.001 &&
							# ray[0].vector_to(inter).angle_between(normal).radians.round > 90 &&
							ray[1].length > 0 &&
							ray[0].vector_to(inter).parallel?(ray[1]) &&
							f.classify_point(inter.transform(trans.inverse)) != 16

							# puts "angle: #{ray[0].vector_to(inter).angle_between(normal).radians.round}"

							[ray[0], inter, inter.distance(ray[0]), ray[0].vector_to(inter).angle_between(normal).radians.round > 90, mesh + [f]]
						else
							nil
						end
					}.reject{|x| x.nil?}.sort_by{|c| c[2]}

					point = intersect.each_with_index.find{|c, index|
						index > 0 && c[3] && intersect[index - 1][3]
					}
					if point.nil?
						point = intersect[0]
					else
						point = point[0]
					end
					# point.nil? ? [ray[0], nil, nil, nil] : point ok
				}.reject{|x| x.nil?}
			}
		end

		def max_planes(mesh, cap_indecies)
			# while true
			ints = project_to_mesh(mesh, cap_indecies)
			# 	if ints.any?{|c| c.any?}
			# 		puts "intersect"
			# 		break
			# 	else
			# 		puts "no intersect, stretch back to find"
			# 		break
			# 	end
			# end
			# puts "ints: #{ints}"
			farest = ints.map{|c|
				if c.empty?
					nil
				else
					c.max_by{|c| c[2]}
				end
			}.reject{|x| x.nil?}
			# puts "farest: #{farest}"
			path = self.chain
			farest.each_with_index.map{|f, i|
				vec = case cap_indecies[i]
				when 0
			 		path[1].vector_to(path[0])
				when 1
					path[-2].vector_to(path[-1])
				end

				# [f[1], f[4].last.normal.transform(Sketchup::InstancePath.new(f[4]).transformation)]
				# vec = f[4].last.normal.transform(Sketchup::InstancePath.new(f[4]).transformation)
				e_vec = f[0].vector_to(f[1])
				angle = vec.angle_between(e_vec).radians
				pt = f[1].offset(vec.normalize)
				[pt, e_vec]
			}
		end

		def trim_to_solid(solid, cap_indecies)
			m_planes = max_planes(solid, cap_indecies)
			# puts "max planes: #{m_planes}"
			m_planes.each_with_index{|pl, i|
				extend_to_plane(pl, cap_indecies[i], self.transformation)
			}
			cap_indecies.each{|cap_index|
				self.set_attribute("cap_#{cap_index}_trim", ["solid", self.chain[- cap_index].to_a,  solid[-1].persistent_id])
			}

			result = perform_boolean_trim(solid[-1])
			if result
				# puts "trim success"
				delete_waste(result)
				return result
			else
				# puts "trim fail"
				return
			end
		end


		def get_picked_cap_face_index(pickray, trans =  self.transformation)

			chain = self.chain
			closest = chain.closest_point_on_path(pickray,trans)
			dist_on_path = chain.distance_along_path(closest[0],trans)
			length = self.length
			if dist_on_path == nil
				#p "point is not on path"
				return 0
			end
			ratio = dist_on_path/length
			if ratio<0.5
				index = 0
			else
				index = 1
			end

			return index

		end


		def get_closest_path_point(pickray, trans =  self.transformation)

			chain = self.chain
			edges = chain.edges
			closest = chain.closest_point_on_path(pickray,trans)
			pt = closest[0]
			edge_index = closest[1]
			edge = edges[edge_index]
			p0 = edge[0].transform(trans)
			p1 = edge[1].transform(trans)
			edge_length = p0.distance(p1)
			dist_to_pt = p0.distance(pt)
			ratio = dist_to_pt / edge_length
			if ratio <= 0.5
				pt_index = chain.index(edge[0])
			else
				pt_index = chain.index(edge[1])
			end

			pt_index

		end

		def get_profile_transform_at_segment(i)

		end

		def extend_start(length)
			path = self.chain
			vector = start_extend_vector
			path[0] = path[0].offset(vector, length)
			self.set_chain(path)
		end


		def extend_end(length)
			path = self.chain
			vector = end_extend_vector
			path[-1] = path[-1].offset(vector, length)
			self.set_chain(path)
		end

		def trim_to_plane(plane, cap_index, trans, redraw = true)
			#plane = plane.map{|c| c.transform trans *self.transformation.inverse}

			@group = @group.make_unique if @group.is_a?(Sketchup::Group)
			@su_defn = @group.definition
			chain_cap = cap_index == 0 ? self.chain[1] : self.chain[-2]
			vector = cap_index == 0 ? self.start_extend_vector : self.end_extend_vector
			# UI.messagebox [self.chain[0], self.chain[-1]].to_s
			projected_chain_cap = Geom.intersect_line_plane([chain_cap, vector].map{|c| c.transform(trans)}, plane)
			# UI.messagebox projected_chain_cap.to_s
			if projected_chain_cap #if there's an intersection

				path = self.chain.path
				path[- cap_index] = projected_chain_cap.transform(trans.inverse)
				self.set_chain(path)
				self.set_attribute("cap_#{cap_index}_trim", ["plane", self.chain[- cap_index].to_a, plane.map{|c| c.transform(trans.inverse).to_a}])
				draw if redraw
			else
				self.delete_attribute("cap#{cap_index}_trim")
			end
		end

		def extend_to_plane(plane, cap_index, trans, redraw = true)
			# ap plane

			@group = @group.make_unique if @group.is_a?(Sketchup::Group)
			@su_defn = @group.definition
			chain_cap = cap_index == 0 ? self.chain[1] : self.chain[-2]

			vector = cap_index == 0 ? self.start_extend_vector : self.end_extend_vector
			# UI.messagebox [self.chain[0], self.chain[-1]].to_s
			projected_chain_cap = Geom.intersect_line_plane([chain_cap, vector].map{|c| c.transform(trans)}, plane)
			# UI.messagebox projected_chain_cap.to_s
			if projected_chain_cap #if there's an intersection
				# projected_chain_cap.offset!(vector, -vector.length * 0.5)
				path = self.chain.path
				self.set_attribute("cap_#{cap_index}_trim", nil)

				path[- cap_index] = projected_chain_cap.transform(trans.inverse)
				vertices = self.get_cap_vertices[cap_index]
				self.set_chain(path)
				# puts "cap index: #{cap_index}"
				#  ap vertices
				if vertices.any?
					# project_vertices_to_plane(vertices, plane, self.transformation)

					e = vertices.group_by{|v|
						v.curve_interior?
					}
					e.each{|curve, verts|
						if curve
							arr = curve.vertices.map{|v|
								v_pos = v.position.transform(trans)
								new_pos = Geom.intersect_line_plane([v.position, vector].map{|c| c.transform(trans)}, plane)
							}
							curve.move_vertices(arr)
						else
							# xx = verts.group_by{|v|
							# 	v_pos = v.position.transform(trans)
							# 	new_pos = Geom.intersect_line_plane([v.position, vector].map{|c| c.transform(trans)}, plane)
							# 	n_vector = v_pos.vector_to(new_pos).transform(trans.inverse).to_a.map{|c| c.round(3)}
							# }
							# xx.sort_by{|k,v|
							# 	Geom::Vector3d.new(k).length
							# }.each{|vector,verts|
							# 	tr = Geom::Transformation.translation(vector)
							# 	verts[0].parent.entities.transform_entities(tr, verts)
							# }

							# xx = verts.group_by{|v|
							# 	v_pos = v.position.transform(trans)
							# 	new_pos = Geom.intersect_line_plane([v.position, vector].map{|c| c.transform(trans)}, plane)
							# 	n_vector = v_pos.vector_to(new_pos).transform(trans.inverse).to_a.map{|c| c.round(3)}
							# }
							# mv = xx.keys.max_by{|k|
							# 	v_vec = Geom::Vector3d.new(k)
							# 	v_vec.length
							# }
							# vv = xx.values.flatten
							# vv[0].parent.entities.transform_entities(Geom::Vector3d.new(mv), vv)


							vvv = verts.map{|v|
								v_pos = v.position.transform(trans)
								new_pos = Geom.intersect_line_plane([v.position, vector].map{|c| c.transform(trans)}, plane)
								n_vector = v_pos.vector_to(new_pos).transform(trans.inverse)
								[v, n_vector]
							}.transpose
							verts[0].parent.entities.transform_by_vectors(vvv[0], vvv[1])
						end
					}
					# check solid
					# VBO::ShapeForge::FixSolid.fix_solid(@group.entities)
				else
					# UI.messagebox "no vertices"
				end
			else
				self.delete_attribute("cap#{cap_index}_trim")
			end
		end


		def get_cap_vertices1()
			pm_caps = [[],[]]
			vertices.each{|v|
				for i in 0..1
					if cap_points(i).map{|c| c.map{|t| t.round(3)}}.include?(v.position.to_a.map{|c| c.round(3)})
						pm_caps[i] << v
					end
				end
			}
			pm_caps
		end

		def vertices_at(junction)

			recent = profile_points_at(junction)
			vertices.find_all{|v| recent.map{|c| c.map{|t| t.round(3)}}.include?(v.position.to_a.map{|c| c.round(3)})}

		end

		def get_cap_vertices()
			if self.chain.length > 2
				recent = profile_points_at_junctions[1..self.chain.length - 2].flatten.map{|pt| pt.to_a}
				junc_verts = vertices.find_all{|v| recent.map{|c| c.map{|t| t.round(3)}}.include?(v.position.to_a.map{|c| c.round(3)})}
				#junc_verts = vertices.find_all{|v| recent.include?(v.position)}
			else
				junc_verts = []
			end

			cap_verts = vertices - junc_verts

			v0 = vertices_at(0)
			v1 = vertices_at(self.chain.length - 1)
			if !v0.empty?
				return [v0, cap_verts - v0]
			elsif !v1.empty?
				return [cap_verts - v1, v1]
			else
				vs = cap_verts.map{|v| v.edges.find_all{|e| e.line[1].parallel?(self.start_extend_vector)}}.flatten.map{|e|
					e.vertices.min_by{|v|
						v.position.distance(self.chain[0])
					}
				}.group_by{|x|
					x.edges.count{|e|
						e.line[1].parallel?(self.start_extend_vector)
					}
				}
				start_verts = (vs[1].to_a + vs[2].to_a.find_all{|v|
					v.edges.find{|e|
						e.line[1].parallel?(self.start_extend_vector) &&
						vs[1].include?(e.other_vertex(v))
					}
				}).uniq
				end_verts = cap_verts - start_verts
				[start_verts, end_verts]
			end
		end


		def get_cap_vertices2()
			if self.chain.length > 2
				recent = profile_points_at_junctions[1..self.chain.length - 2].flatten.map{|pt| pt.to_a}
				junc_verts = vertices.find_all{|v| recent.map{|c| c.map{|t| t.round(3)}}.include?(v.position.to_a.map{|c| c.round(3)})}
				#junc_verts = vertices.find_all{|v| recent.include?(v.position)}
			else
				junc_verts = []
			end
			cap_verts = vertices - junc_verts
			pm_caps = []
			v0 = vertices_at(0)
			v1 = vertices_at(self.chain.length - 1)
			if !v0.empty?
				return [v0, cap_verts - v0]
			elsif !v1.empty?
				return [cap_verts - v1, v1]
			else
				for i in 0..1
					edges = case i
					when 0
						vector = self.start_extend_vector
						neighbour = vertices_at(1)
						if neighbour.empty? # 1 is a distored cap
							self.entities.find_all{|e|
								e.is_a?(Sketchup::Edge) && e.line[1].parallel?(vector)
							}
						else
							neighbour.map{|v| v.edges.find{|e| v.position.vector_to(e.other_vertex(v).position).samedirection?(vector)}}
						end
					when 1
						vector = self.end_extend_vector
						if self.chain.length > 2
							neighbour = vertices_at(self.chain.length - 2)
							neighbour.map{|v| v.edges.find{|e| v.position.vector_to(e.other_vertex(v).position).samedirection?(vector)}}
						else
							neighbour = vertices_at(0)
							if neighbour.empty? #0 is a distored cap
								self.entities.find_all{|e|
									e.is_a?(Sketchup::Edge) && e.line[1].parallel?(vector)
								}
							else
								neighbour.map{|v| v.edges.find{|e| v.position.vector_to(e.other_vertex(v).position).samedirection?(vector)}}
							end
						end
					end
					pm_caps << cap_verts.find_all{|v| edges.any?{|e| e.vertices.include?(v)}}
				end
			end
			trimmed = cap_verts - pm_caps.flatten
			trimmed.each{|vertex|
				distances = pm_caps.map{|cap|
					plane = Geom.fit_plane_to_points(cap.map{|v| v.position})
					vertex.position.distance(vertex.position.project_to_plane(plane))
				}
				index = distances.index(distances.min)
				pm_caps[index] << vertex
			}
			pm_caps
		end


		def get_cap_faces()

			return [get_cap_face(true),get_cap_face(false)]

		end


		def get_perpendicular_cap_faces()

			faces = self.get_cap_faces()
			if faces[0]
				faces[0] = nil if !(faces[0].normal.samedirection?(start_extend_vector()))
			end
			if faces[1]
				faces[1] = nil if !(faces[1].normal.samedirection?(end_extend_vector()))
			end

			return faces

		end

		def end_extend_vector()

			path = self.chain
			return path[-2].vector_to(path[-1]).normalize

		end


		def start_extend_vector()

			path = self.chain
			return path[1].vector_to(path[0]).normalize

		end

		def set_attribute(key, val)
			return if @su_defn.nil?
			@su_defn.set_attribute(@@dict,key,val)
		end

		def get_attribute(key)
			return if @su_defn.nil?
			@su_defn.get_attribute(@@dict,key)
		end
		def delete_attribute(key)
			@su_defn.delete_attribute(@@dict,key)
		end

		#private

		def copy_group_dict_to_defn_deprecated()

			dict = nil
			dicts = @group.attribute_dictionaries
			dict = dicts[@@dict] if dicts

			if dict
				dict.each {|key,val|
					if key and key != ""
						@su_defn.set_attribute(@@dict,key,val)
					end
				}
				@group.delete_attribute(@@dict)
			end

		end


		def copy_attributes_to(dest_instance)

			dicts = @su_defn.attribute_dictionaries
			dest_defn = dest_instance.definition
			dest_instance.layer = self.layer

			if dicts
				dicts.each {|dict|
					dict.each_pair {|key,value| dest_defn.set_attribute(dict.name,key,value)}
				}
			end

		end


		def clear_existing_edges()

			@group.make_unique if @group.kind_of?(Sketchup::Group)
			group_ents = self.entities
			edges = group_ents.grep(Sketchup::Edge)
			text = group_ents.grep(Sketchup::Text)
			group_ents.erase_entities(edges)
			group_ents.erase_entities(text)

		end



		def get_layer_by_name(layer_name)

			layers = Sketchup.active_model.layers
			layer = layers[layer_name]
			if layer
				return layer
			else
				return layers[0]
			end

		end


		def get_material()

			mat_name = self.material_name
			mats = Sketchup.active_model.materials
			if mat_name
				mat = mats.find{|m| m.name == mat_name || m.display_name == mat_name}
				if mat
					# puts "get material: #{mat_name}"
					return mat
				end
			end

			return nil

		end


		def fix_vector!(vec)

			x = vec.x
			y = vec.y
			z = vec.z

			x = x.abs if x == 0.0
			y = y.abs if y == 0.0
			z = z.abs if z == 0.0

			vec.set!(x,y,z)

		end

		class TrimException < RuntimeError

		end

		def extrude_mode_edges
			if self.profile.extrude_mode == "normal_mode"
				junction_edges = self.junctions.map{|loops|
					loops.map{|lo|
						(lo + [lo[0]]).each_cons(2).to_a
					}
				}.flatten(2)
				self.entities.find_all{|e|
					e.is_a?(Sketchup::Edge) &&
					junction_edges.any?{|pts|
						e_vers = e.vertices.map{|v| v.position.to_a.map{|c| c.round(3)}}
						j_vers = pts.map{|pt| pt.to_a.map{|c| c.round(3)}}
						e_vers == j_vers || e_vers == j_vers.reverse
					}
				}.each{|edge|
					edge.smooth = false
					edge.soft = false
				}
			end
		end
		def soften(angle, ents = self.entities)

			return if angle == 180
			angle = angle.degrees
			# angle = self.smooth_angle.degrees
			edges = ents.find_all { |e| e.is_a?(Sketchup::Edge)}
			edges.each { |edge|
				faces = edge.faces
				if faces.length == 2
					n1 = faces[0].normal
					n2 = faces[1].normal
					angle2 = n1.angle_between(n2)
					# puts "angle2: #{angle2.radians}"
					# puts "angle: #{angle.radians}"
					if angle2.radians.round(1) > angle.radians.round(1)
						edge.soft = false
						edge.smooth = false
					end
				end
			}
			extrude_mode_edges
			return nil
		end



		def validate_for_trim(inst)

			if @group.class == Sketchup::Group
				@group = @group.make_unique
				@su_defn = @group.definition
			end

			pm = ForgeElement.new(inst)
			if pm.definition == self.definition
				inst = inst.make_unique
			end

			return inst

		end


		def prepare_end_for_trim_(trimmer_inst,cap_index, trans)

			begin
				#trans = self.transformation#Geom::Transformation.new# if trans.nil?
				path = self.chain
				cf = get_cap_faces()[cap_index]
				if cf.nil?
					draw
					cf = get_cap_faces()[cap_index]
				end
				push_length = push_cap_face(cf)
				max_distances_to_entity = []
				max_distance_to_entity = get_max_perp_distance_from_face_to_entity(cf, trimmer_inst, trans)
				pull_length = pull_cap_face(cf, max_distance_to_entity, push_length)
				end_offset_distance = pull_length - push_length
				offset_chain_end(cap_index,end_offset_distance)
			end
		end

		def prepare_end_for_trim(trimmer_inst,cap_index, trans = Geom::Transformation.new)

			begin
				solid = trimmer_inst
				cf = self.get_cap_vertices()[cap_index]
				points = self.cap_points(cap_index).map{|c| c.transform(self.transformation)}
				if cf.nil?
					return
				end
				case cap_index
				when 0
					vector = self.start_extend_vector.transform(self.transformation)
				when 1
					vector = self.end_extend_vector.transform(self.transformation)
				end
				cal = points.map{|point|
					ray = [point, vector]
					max_dist = get_ray_max_distance(solid.entities.grep(Sketchup::Face).map{|c|
						thru_face(ray, c, solid.transformation)
					}.delete_if{|c| c.nil? || c[0].nil? || c[1] == Sketchup::Face::PointOutside}.map{|c|
						[c[0], c[1], c[0].distance(point)]
					})
					max_dist.nil? ? 0 : max_dist[2]
				}.max
				vector.length = cal
				vector = vector.transform(self.transformation.inverse)
				trans = Geom::Transformation.translation(vector)
				self.definition.entities.transform_entities(trans, cf)

				end_offset_distance = cal
				offset_chain_end(cap_index,end_offset_distance)
			end
		end


		def push_cap_face(cf)

			range = get_range_perpindicular_edge_length(cf.outer_loop.vertices)
			push_length = range.min
			push_length -= 0.01
			cf.pushpull(-push_length)

			return push_length

		end


		def pull_cap_face(cap_face,distance,push_length)

			if distance == nil
				raise TrimException, "Cannot Trim.  Ensure Shape Member path intersects the second object.", caller
			end

			if distance
				normal = cap_face.normal
				normal.length = distance+push_length
				cap_face.pushpull(distance)
			end

			return distance

		end


		def offset_chain_end(cap_index,distance)

			path = self.chain
			if cap_index == 0
				vec = start_extend_vector()
				pt_index = 0
			else
				vec = end_extend_vector()
				pt_index = -1
			end
			vec.length = distance
			path[pt_index] = path[pt_index].offset(vec)
			self.set_chain(path)

		end

		def perform_boolean_trim(trimmer_inst)

			name = @group.name
			instances = self.definition.instances
			defn_name = @su_defn.name

			dicts_hash = {}
			dicts = @su_defn.attribute_dictionaries
			dicts.each {|dict|
				dict_name = dict.name
				dict_hash = {}
				dict.each {|key,val| dict_hash[key] = val}
				dicts_hash[dict_name] = dict_hash
			}

			# result = trimmer_inst.trim(self.instance)
			result = VBO::ShapeForge::Trim.trim(self.instance, trimmer_inst)
			return unless result
			result.name = name

			defn = result.entities.parent

			dicts_hash.each {|dict_name,dict|
				dict.each {|key,val| defn.set_attribute(dict_name,key,val)}
			}

			if instances.length > 0
				#@group = instances.length > 1 ? result.to_component : result
				self.instance = result
				instance.name = name if instance.respond_to?(:name=)
				@su_defn = defn
				@su_defn.name = defn_name
				# instances.each {|inst|
				# 	inst.definition = @su_defn if inst.valid?
				# }
			end

			defn

		end

		def delete_waste(defn)
			ents = defn.entities

			faces = ents.grep(Sketchup::Face)
			connected_faces = []
			connected_area_sum = []
			area_sum = 0

			faces.each_index {|i|
				area_sum = 0
				connected_faces = faces[i].all_connected
				connected_faces = connected_faces.grep(Sketchup::Face)
				connected_faces.each {|f| area_sum += f.area}
				connected_area_sum[i] = area_sum
			}
			uniq_area_sum = connected_area_sum.uniq

			while ((uniq_area_sum.min) != (uniq_area_sum.max))
				min_area = uniq_area_sum.min
				face_index = connected_area_sum.index(min_area)
				reference_face = faces[face_index]
				connected_faces = reference_face.all_connected
				ents.erase_entities(connected_faces)
				uniq_area_sum.delete(min_area)
			end
			#
		end


		def project_vertices_to_plane(verts,plane, pm_trans)

			#pm_trans = self.transformation
			normal = get_normal_of_vertices(verts).transform(pm_trans)

			vectors = []
			verts.each {|v|
				p1 = v.position.transform(pm_trans)
				line = [p1,normal]
				p2 = Geom.intersect_line_plane(line,plane)
				vectors.push(p1.vector_to(p2))
			}

			vectors = vectors.collect {|vec| vec.transform(pm_trans.inverse)}

			if self.profile.is_1d?
				curve_edge = verts[0].edges.find {|edge| edge.curve}
				curve = curve_edge.curve
				new_positions = []
				vectors.each_index {|i| new_positions[i] = verts[i].position.transform(Geom::Transformation.new(vectors[i]))}
				curve.move_vertices(new_positions)
			else
				common_face = (verts[0].faces)&(verts[1].faces)&(verts[2].faces)
				common_face = common_face[0]
				if common_face
					outer_loop_verts = common_face.outer_loop.vertices
					loops = []
					face_loops = common_face.loops
					face_loops.each_index {|i|
						loop_verts = face_loops[i].vertices
						loops<<face_loops[i].vertices unless face_loops[i].outer?
					}
					ents = self.entities
					ents.erase_entities(common_face)

					new_face_pts = []
					vectors.each_index {|i| new_face_pts[i] = verts[i].position.transform(Geom::Transformation.new(vectors[i]))}
					ents.transform_by_vectors(verts,vectors)
					ents.add_face(new_face_pts).material = self.get_material

					loops.each {|loop_verts|
						loop_vectors = []
						loop_verts.each {|v|
							p1 = v.position.transform(pm_trans)
							line = [p1,normal]
							p2 = Geom.intersect_line_plane(line,plane)
							loop_vectors.push(p1.vector_to(p2))
						}

						loop_vectors = loop_vectors.collect {|vec| vec.transform(pm_trans.inverse)}
						new_loop_pts = []
						loop_vectors.each_index {|i| new_loop_pts[i] = loop_verts[i].position.transform(Geom::Transformation.new(loop_vectors[i]))}
						ents.transform_by_vectors(loop_verts,loop_vectors)
						hole_face = ents.add_face(new_loop_pts)
						hole_face.erase!
					}
				end
			end

		end


		def get_closest_cap_verts_to_point(point)

			cap_vertices = self.get_cap_vertices()
			trans = self.transformation
			distance_to_point = []
			cap_vertices.delete(nil)
			if cap_vertices.empty?
				raise TrimException, "Cannot Trim.  Shape Member must have an unmodified cap face.", caller
			end

			cap_vertices.each_index {|index|
				verts = cap_vertices[index]
				box = Geom::BoundingBox.new
				face_pts = verts.collect {|v| v.position.transform(trans)}
				box.add(face_pts)
				face_center = box.center
				distance_to_point.push(face_center.vector_to(point).length)
			}

			min_distance = distance_to_point.min
			min_index = distance_to_point.index(min_distance)

			return cap_vertices[min_index]

		end
	end

end
