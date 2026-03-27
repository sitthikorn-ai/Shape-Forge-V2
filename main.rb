require 'sketchup.rb'
require 'set'
Sketchup.require File.join(File.dirname(__FILE__), 'tools')
Sketchup.require File.join(File.dirname(__FILE__), 'member')
Sketchup.require File.join(File.dirname(__FILE__), 'methods')
Sketchup.require File.join(File.dirname(__FILE__), 'graph')
#Sketchup.require File.join(File.dirname(__FILE__), 'overlay')
module VBO
	module ShapeForge
		def self.random_sketchup_color
			red = rand(256)  # Random number between 0 and 255
			green = rand(256)  # Random number between 0 and 255
			blue = rand(256)  # Random number between 0 and 255
			alpha = 255  # Fully opaque
			color = Sketchup::Color.new([red, green, blue, alpha])
			return color
		end

		def self.debug(message)
			if @debug_mode
				caller_info = caller[0].split(':')
				method_name = caller_info[-1]
				caller_location = caller_locations(1, 1)[0]
				caller_class = Module.nesting[0]
				puts "#{caller_class.name}##{method_name.gsub('in ','').delete("'`")}:"
				puts message
			end
		end
		def self.enable_debug_mode
			@debug_mode = true
		end
		def self.disable_debug_mode
			@debug_mode = false
		end
		def self.hilight(items, path = nil)
			Sketchup.active_model.tools.pop_tool while Sketchup.active_model.tools.active_tool.to_s.include?('Pick')
			Sketchup.active_model.tools.push_tool(SelHilight.new(items, path))
		end
		def self.hilights_off
			tools = Sketchup.active_model.tools
			if Sketchup.version.to_i.ceil > 18
				tools.pop_tool if tools.active_tool.to_s.include?("SelHilight")
			else
				Sketchup.active_model.select_tool(nil)
			end
		end

		def self.mat_name(mat)
			mat.respond_to?(:name) ? mat.name : "Default"
		end
		def self.model_members
			definitions = Sketchup.active_model.definitions.reject{|d| d.count_used_instances == 0}
			definitions.each{|d|
				if d.group? && d.instances.length > 1 && VBO::ShapeForge::Identify.profile_member?(d.instances[0])
					d.instances.each{|i|
						i.make_unique
					}
				end
			}
			list = definitions.map{|d|
				VBO::ShapeForge::Identify.profile_member?(d.instances[0])
			}.delete_if{|c|
				c.nil? || c.definition.instances.empty?
			}.group_by{|c| c.profile.fullname}
			list.map{|k,v|
				[
					k, v.group_by{|c|
					profile = c.profile
					#c.material_name = mat_name(c.instance.material)
					#profile.set_from_profile_member(c)
					profile.to_s
				}]
			}.to_h
		end

		def self.active_members
			Sketchup.active_model.active_entities.map{|c| VBO::ShapeForge::Identify.profile_member?}.reject{|c| c.nil?}
		end

		def self.home_profiles
			Sketchup.active_model.definitions.map{|d|
				VBO::ShapeForge::Identify.profile_member?(d.instances[0])
			}.delete_if{|c|
				c.nil? || c.definition.instances.empty?
			}.group_by{|c|
				c.profile.fullname
			}.map{|k,v|
				[
					k,
					v.group_by{|c| c.profile.material_name }.map{|kk,vv|
						[
							kk,
							vv.group_by{|c| Sketchup.active_model.layers[c.profile.layer_name].display_name }.map{|kkk,vvv|
								[
									kkk,
									vvv[0].profile.to_s
								]
							}.to_h
						]
					}.to_h
				]
			}.to_h
		end

		def self.numeric?(str)
			Float(str) != nil rescue false
		end
		def self.model_profiles
			list = Sketchup.active_model.definitions.map{|d| VBO::ShapeForge::Identify.profile_member?(d.instances[0])}.delete_if(&:nil?).group_by{|c| [c.name, c.profile.outer_loop.to_s, c.profile.holes.to_s, c.profile.width.to_s, c.profile.height.to_s].join}
			list.map{|k,v| [v[0].profile.fullname, v.map{|c| c.profile}.uniq]}.to_h
		end
		def self.model_profiles_fields
			fields = ["width", "height", "placement_point",
				"mirror.to_s",
				"rotation",
				"x_offset",
				"y_offset",
				"smooth_angle",
				"x_scale",
				"y_scale",
				"dimension",
				"material_name",
				"layer_name"]
			list = Sketchup.active_model.definitions.map{|d| VBO::ShapeForge::Identify.profile_member?(d.instances[0])}.delete_if(&:nil?).group_by{|c| [c.name, c.profile.outer_loop.to_s, c.profile.holes.to_s, c.profile.width.to_s, c.profile.height.to_s].join}
			list.map{|k,v| [v[0].profile.fullname, v.map{|c| fields.zip([c.profile.width, c.profile.height] + c.profile.to_s.delete("\n").split('|extended|')[1].split('|').map{|c| numeric?(c) ? eval(c) : c}).to_h}].uniq}.to_h
		end
		def solid_trimmer?(defi)

		end
		def self.selection_members(ent = Sketchup.active_model.selection)
			ent.map{|c| VBO::ShapeForge::Identify.profile_member?(c)}.delete_if{|c| c.nil?}
		end
		def self.multi_trim_to_plane(plane)
			selection_members.each{|pm|
				caps = [pm.chain[0], pm.chain[-1]].map{|c| c.transform(pm.transformation)}.each_with_index.map{|c, i|
				vector = i == 0 ? pm.start_extend_vector.transform(pm.transformation) : pm.end_extend_vector.transform(pm.transformation)
				c.distance(Geom.intersect_line_plane([c,vector],plane))
				}
				#puts caps
				cap = caps.index{|c| caps.min}
				trans = Geom::Transformation.new
				pm.trim_to_plane(plane, cap, trans)
			}
		end
		def self.collect_all_active_instances(entity)
			results = []
			queue = []
			entity_transformation = (entity.respond_to?(:transformation)) ?
									entity.transformation :
									IDENTITY
			queue.push([[entity], entity_transformation])
			until queue.empty?
			  path, transformation = *queue.shift
			  outer = path.first
			  if outer.parent.is_a?(Sketchup::Model) || outer.parent.nil?
				if entity.model.active_path.nil? || (entity.model.active_path - path).empty?
				  results << path
				end
			  else
				instances = (outer.is_a?(Sketchup::ComponentDefinition)) ?
							outer.instances :
							(outer.respond_to?(:parent) && outer.parent.respond_to?(:instances)) ?
							outer.parent.instances :
							[]
				instances.each{ |instance|
				  queue.push [[instance].concat(path), instance.transformation * transformation]
				}
			  end
			end
			return results
		end

		def self.model_members_definitions
			list = Sketchup.active_model.definitions.map{|d| VBO::ShapeForge::Identify.profile_member?(d.instances[0])}.delete_if(&:nil?)
		end

		def self.get_valid_filename(f_name)
			illegal="\\\/:*?\"<>|"
			return f_name.delete(illegal)
		end

		def self.next_vertex(ent, path, closed)
			return if path.empty?
			vertex = path[-1]
			from = path - [vertex]
			if !from.empty?
				edge = vertex.edges.find_all{|e| ent.include?(e) && !from.any?{|f| e.vertices.include?(f)}}.max_by{|e|
					vector1 = vertex.position.vector_to from[-1]
					vector2 = vertex.position.vector_to(e.other_vertex(vertex).position)
					vector1.angle_between(vector2)
				}
			else
				edge = vertex.edges[0]
				edge = nil if !ent.include?(edge)
			end
			if edge.nil?
				if closed && path.length > 2 && path[-1].edges.any?{|e| e.other_vertex(path[-1]) == path[0]}
					path + [path[0]]
				else
					path
				end
			else
				next_vertex(ent, path + [edge.other_vertex(vertex)], closed)
			end
		end

		def self.get_last_profile_path
			begin
				default_path = ""
				last_path = Sketchup.read_default("VBO ShapeForge","LastProfilePath", default_path)
			rescue
				self.save_last_profile_path("")
				last_path = ""
			end
			last_path
		end

		def self.get_last_assembly_path
			begin
				default_path = ""
				last_path = Sketchup.read_default("VBO ShapeForge","LastForgeStructurePath", default_path)
			rescue
				self.save_last_assembly_path(path)
				last_path = ""
			end
			last_path
		end

		def self.save_last_profile_path(path)
			path.gsub!(/\\/,"\/")
			last_path = Sketchup.write_default("VBO ShapeForge","LastProfilePath", path)
			last_path
		end

		def self.save_last_assembly_path(path)
			path.gsub!(/\\/,"\/")
			last_path = Sketchup.write_default("VBO ShapeForge","LastForgeStructurePath", path)
			last_path
		end

		def self.get_paths(ent)
			ent = ent.to_a.grep(Sketchup::Edge)
			vertices = ent.map{|c| c.vertices}.flatten.uniq
			return [] if vertices.empty?
			starts = vertices.find_all{|c| c.edges.find_all{|e| ent.include?(e)}.length == 1}
			loops = []
			while starts.empty? && !vertices.empty?
				start = vertices[0]
				path = next_vertex(ent, [start], true)
				loops << path
				#ent = ent.find_all{|e| (e.vertices - path).length > 0}
				ent.delete_if{|e| (e.vertices - path).length == 0}
				vertices = ent.map{|c| c.vertices}.flatten.uniq
				starts = vertices.find_all{|c| c.edges.find_all{|e| ent.include?(e)}.length == 1}
			end
			paths = []
			while !starts.empty?
				start = starts[0]
				path = next_vertex(ent, [start], false)
				paths << path
				starts -= [start, path[-1]]
				ent = ent.find_all{|e| (e.vertices - path).length > 0}
			end
			loops + paths
		end

		def self.collect_paths(ent, path)
			list = [{path => get_paths(ent)}]
			nested = ent.find_all{|e| e.respond_to?(:definition) && Identify.profile_member?(e).nil?}
			unless nested.empty?
				nested.each{|c|
					list += collect_paths(c.definition.entities, path + [c])
				}
			end
			list.flatten
		end

		def self.best_path_from_vertex(vertex, other, path)
			edge = vertex.edges.find_all{|c| !path.include?(c.other_vertex(vertex))}.max_by{|c| vertex.position.vector_to(c.other_vertex(vertex).position).angle_between(vertex.position.vector_to(other))}
			if edge.nil?
				path
			else
				point = edge.other_vertex(vertex)
				best_path_from_vertex(point, vertex, [point] + path)
			end
		end

		def self.best_path_from_edge(edge, loop = false)
			return edge.curve.vertices if edge.curve
			a = best_path_from_vertex edge.start, edge.end, edge.vertices
			b = best_path_from_vertex edge.end, edge.start, edge.vertices.reverse
			path = (a + b.reverse).uniq
			path << path[0] if loop && (path[0].edges & path[-1].edges).length > 0
			path
		end

		def self.paths(ent = Sketchup.active_model.selection, path = Sketchup.active_model.active_path.to_a)
			collect_paths(ent, path).map{|c| [c.keys[0], c.values[0]]}.delete_if{|c| c[1].empty?}.to_h
		end

		def self.build_branch(profile, sel = Sketchup.active_model.selection, ent = Sketchup.active_model.active_entities)
			group = ent.add_group
			entities = group.entities
			edges = sel.find_all { |e| e.is_a?(Sketchup::Edge) && e.curve.nil?}
			curves = sel.find_all { |e| e.is_a?(Sketchup::Edge) && e.curve}.map{|c| c.curve}.uniq
			vertices = (edges.map{|c| c.vertices} + curves.map{|c| [c.vertices[0], c.vertices[-1]]}).flatten.uniq

			(edges + curves).each{|set|
				points = set.vertices.map{|c| c.position}
				pm = VBO::ShapeForge::ForgeElement.add(entities, points)
				pm.set_from_profile!(profile)
			}
			group.definition.set_attribute("VBO ShapeForge", "Branch", true)
			Branch.new(group)
		end

		def self.build_assembly_from_ents(
			assembly,
			sel = Sketchup.active_model.selection,
			ent = Sketchup.active_model.active_entities,
			inherit = nil,
			type = 'continuous'
		)
			if sel.length == 1 && sel[0].is_a?(Sketchup::Edge)
				as = VBO::ShapeForge::ForgeStructure.add(ent)
				as.fence = assembly.fence
				as.set_chain(sel[0].vertices.map{|c| c.position})
				groups = [as.draw]
			else
				paths = paths(sel)
				groups = []
				paths.each{|instance_path, path_array|
					entities = ent
					entities = sel[0].parent.entities if ent.nil?
					trans = Sketchup::InstancePath.new(instance_path).transformation
					path_array.each{|suggest_path|
						next if suggest_path.length < 2
						as = VBO::ShapeForge::ForgeStructure.add(entities)
						as.fence = assembly.fence
						as.set_chain(suggest_path.map{|c| c.position.transform(trans)})
						groups << as.draw
					}
				}
			end
			# sel.find_all{|c| c.is_a?(Sketchup::Edge) || c.is_a?(Sketchup::ConstructionPoint)}.each{|c| c.erase! unless c.to_s.include?('Delete')}
			groups
		end

		def self.build_from_ents(
			profile,
			sel = Sketchup.active_model.selection,
			ent = Sketchup.active_model.active_entities,
			inherit = nil,
			type = 'continuous'
		)
			paths = paths(sel)
			if ent.nil?
				Sketchup.active_model.start_operation("VBO ShapeForge - Build", true)
			else
				Sketchup.active_model.start_operation("VBO ShapeForge - Build", true)
			end
			groups = []
			paths.each{|instance_path, path_array|
				#g = path_array[0][0].parent.entities.add_group
				#entities =  g.entities
				entities = ent
				entities = sel[0].parent.entities if ent.nil?
				trans = Sketchup::InstancePath.new(instance_path).transformation
				path_array.each{|suggest_path|
					pm = VBO::ShapeForge::ForgeElement.add(entities, suggest_path.map{|c| c.position.transform(trans)})
					unless inherit.nil?
						inherit.each_with_index{|att,i|
							pm.set_attribute("cap_#{i}_trim", att)
						}
					end
					pm.set_from_profile!(profile, type)
					groups << pm.instance_variable_get(:@group)
				}
				#entities.find_all{|c| c.is_a?(Sketchup::Edge)}.each{|c| c.erase!  unless c.to_s.include?('Delete')}
				#g.explode
				#instance_path[-1].explode if instance_path.length > 0
			}
			sel.find_all{|c| c.is_a?(Sketchup::Edge) || c.is_a?(Sketchup::ConstructionPoint)}.each{|c| c.erase! unless c.to_s.include?('Delete')}

			Sketchup.active_model.commit_operation
			groups
		end

		def self.detect_profile_and_path(entity)
			return nil unless entity.respond_to?(:definition)
			defn = entity.definition
			ents = defn.entities
			faces = ents.grep(Sketchup::Face)
			return nil if faces.length < 3

			trans = entity.transformation

			# Find end cap pairs: same area, same vertex count, no shared edges
			tolerance = 0.01
			candidates = []
			faces.combination(2).each do |f1, f2|
				next if (f1.area - f2.area).abs > tolerance
				next if f1.vertices.length != f2.vertices.length
				next if f1.edges.any? { |e| f2.edges.include?(e) }
				candidates << [f1, f2]
			end
			return nil if candidates.empty?

			# Pick the candidate pair with most vertices (most complex cross-section)
			best_pair = candidates.max_by { |pair| pair[0].vertices.length }
			profile_face = best_pair[0]
			opposite_face = best_pair[1]

			# Determine if this is a straight extrusion or curved path
			# Try to trace longitudinal edges from profile_face vertices
			profile_edges_set = Set.new(profile_face.edges)
			opposite_edges_set = Set.new(opposite_face.edges)

			# Find longitudinal edges: edges connected to profile_face vertices but not part of the face
			start_vertices = profile_face.vertices
			longitudinal_chains = []

			start_vertices.each do |sv|
				chain_pts = [sv.position.transform(trans)]
				current_vertex = sv
				visited = Set.new([current_vertex])
				max_steps = faces.length * 2

				max_steps.times do
					# Find next edge: not on profile_face, not on opposite_face, leads away
					next_edge = current_vertex.edges.find { |e|
						!profile_edges_set.include?(e) &&
						!visited.include?(e.other_vertex(current_vertex)) &&
						e.faces.any? { |f| f != profile_face && f != opposite_face }
					}
					break unless next_edge

					next_vertex = next_edge.other_vertex(current_vertex)
					chain_pts << next_vertex.position.transform(trans)
					visited << next_vertex

					# Check if we reached the opposite face
					if opposite_face.vertices.include?(next_vertex)
						break
					end

					# Continue along longitudinal direction: find the edge from next_vertex
					# that continues in a similar direction (not a cross-section edge)
					current_dir = current_vertex.position.vector_to(next_vertex.position)
					current_vertex = next_vertex

					# Find edges from current_vertex that are NOT cross-section edges
					# Cross-section edges connect vertices that are all on the same "ring"
					candidate_edges = current_vertex.edges.select { |e|
						other = e.other_vertex(current_vertex)
						!visited.include?(other) &&
						!opposite_edges_set.include?(e) &&
						!profile_edges_set.include?(e)
					}

					# Prefer edges that continue in a similar direction
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

					break if opposite_face.vertices.include?(next_vertex)
				end

				longitudinal_chains << chain_pts if chain_pts.length >= 2
			end

			# Determine the path from longitudinal chains
			if longitudinal_chains.empty?
				# Fallback: straight path between face centers
				c1 = Geom::Point3d.new(profile_face.bounds.center).transform(trans)
				c2 = Geom::Point3d.new(opposite_face.bounds.center).transform(trans)
				chain_points = [c1, c2]
			else
				# Build path from midpoints of each cross-section level
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
				# Ensure at least 2 points
				if chain_points.length < 2
					c1 = Geom::Point3d.new(profile_face.bounds.center).transform(trans)
					c2 = Geom::Point3d.new(opposite_face.bounds.center).transform(trans)
					chain_points = [c1, c2]
				end
			end

			# Create Shape from the profile face
			profile = VBO::ShapeForge::Shape.new(profile_face)

			# Set name from Group/Component name
			entity_name = entity.name.to_s.strip
			if entity_name.empty? && entity.respond_to?(:definition)
				entity_name = entity.definition.name.to_s.strip
			end
			entity_name = "Shape Forge" if entity_name.empty?
			profile.name = entity_name

			[profile, chain_points]
		end

		def self.object_to_shape_forge
			model = Sketchup.active_model
			sel = model.selection.to_a

			targets = sel.select { |e|
				(e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
				!VBO::ShapeForge::Identify.profile_member?(e)
			}

			if targets.empty?
				UI.messagebox("Select a source Group or Component first, then click Object to Shape Forge.")
				return
			end

			model.selection.clear
			targets.each { |entity| model.selection.add(entity) if entity.valid? }
			model.tools.push_tool(ObjectToForgeTool.new(targets.select(&:valid?)))
		end

		def self.joint_shape_forge
			model = Sketchup.active_model
			members = selection_members(model.selection.to_a)
			model.tools.push_tool(VBO::ShapeForge::JointShapeForgeTool.new(members))
		end

		def self.auto_join_member_chains(chain_a, chain_b, tolerance = 1.mm)
			return nil unless chain_a.is_a?(Array) && chain_b.is_a?(Array)
			return nil if chain_a.length < 2 || chain_b.length < 2

			joined_by_extension = join_member_chains_by_extension(chain_a, chain_b, tolerance)
			return joined_by_extension if joined_by_extension && joined_by_extension.length >= 2

			pairs = [
				[0, 0, chain_a.first.distance(chain_b.first)],
				[0, 1, chain_a.first.distance(chain_b.last)],
				[1, 0, chain_a.last.distance(chain_b.first)],
				[1, 1, chain_a.last.distance(chain_b.last)]
			]
			end_a, end_b, distance = pairs.min_by { |item| item[2] }

			joined_a = end_a == 0 ? chain_a.reverse : chain_a.clone
			joined_b = end_b == 1 ? chain_b.reverse : chain_b.clone

			path = joined_a.dup
			if distance <= tolerance
				path.concat(joined_b[1..-1] || [])
			else
				path.concat(joined_b)
			end

			clean_chain_points(path, tolerance)
		end

		def self.join_member_chains_by_extension(chain_a, chain_b, tolerance = 1.mm)
			candidates_a = [
				chain_a.clone,
				chain_a.reverse
			]
			candidates_b = [
				chain_b.clone,
				chain_b.reverse
			]

			best = nil

			candidates_a.each do |oriented_a|
				next if oriented_a.length < 2
				a_end = oriented_a.last
				a_dir = oriented_a[-2].vector_to(oriented_a[-1])
				next if a_dir.length <= tolerance

				candidates_b.each do |oriented_b|
					next if oriented_b.length < 2
					b_start = oriented_b.first
					b_dir = oriented_b[1].vector_to(oriented_b[0])
					next if b_dir.length <= tolerance

					line_a = [a_end, a_dir]
					line_b = [b_start, b_dir]

					meet = Geom.intersect_line_line(line_a, line_b)
					point_a = meet
					point_b = meet

					if meet.nil?
						closest = Geom.closest_points(line_a, line_b) rescue nil
						next unless closest && closest.length == 2
						point_a, point_b = closest
						meet = Geom.linear_combination(0.5, point_a, 0.5, point_b)
					end

					next unless point_a && point_b && meet
					next unless extension_forward?(a_end, a_dir, point_a, tolerance)
					next unless extension_forward?(b_start, b_dir, point_b, tolerance)

					score = point_a.distance(point_b) + a_end.distance(point_a) + b_start.distance(point_b)
					path = oriented_a[0...-1] + [meet] + (oriented_b[1..-1] || [])
					path = clean_chain_points(path, tolerance)
					next if path.length < 2

					best = [score, path] if best.nil? || score < best[0]
				end
			end

			best ? best[1] : nil
		end

		def self.extension_forward?(origin, direction, target, tolerance = 1.mm)
			return false unless origin && direction && target
			vec = origin.vector_to(target)
			return true if vec.length <= tolerance
			direction.dot(vec) >= -tolerance
		end

		def self.clean_chain_points(points, tolerance = 1.mm)
			return [] unless points.is_a?(Array)
			cleaned = []
			points.each do |pt|
				next unless pt.respond_to?(:distance)
				next if cleaned.any? && cleaned.last.distance(pt) <= tolerance
				cleaned << pt
			end
			cleaned
		end

		def self.mid_point(a,b)
			(0..2).to_a.map{|i| (a[i] + b[i]) /2}
		end

		def self.align_table(a)
			[a[0], mid_point(a[0], a[1]), a[1], mid_point(a[0], a[2]), mid_point(a[0], a[3]), mid_point(a[1], a[3]), a[2], mid_point(a[2], a[3]), a[3]]
		end

		def self.load_last_profile
			#last_profile = Sketchup.read_default("VBO ShapeForge", "LastProfile")
			#last = !last_profile.nil? &&!last_profile.empty? ? VBO::ShapeForge::Shape.new(last_profile) : VBO::ShapeForge::Shape.new(File.join(File.dirname(__FILE__), 'examples/IBeam - 75 x 150.skp'))
			if @profile_dialog.temp_profile.nil?
				@last_profile = nil if @last_profile.nil? || @last_profile.points.length < 2
				@last_profile = VBO::ShapeForge::Shape.new(File.join(File.dirname(__FILE__), 'examples/IBeam - 75 x 150.skp')) if @last_profile.nil?
				@last_profile
			else
				@last_profile = @profile_dialog.temp_profile
			end
		end
		def self.save_last_profile(profile)
			@last_profile = profile
		end
		def self.load_last_junctions_style
			@junctions_style = "continuous" if @junctions_style.nil?
			@junctions_style
		end
		def self.save_last_junctions_style(jstyle)
			@junctions_style = jstyle
		end
		def self.main
			last = load_last_profile
			@options = Options.new if @options.nil?

			if !Sketchup.active_model.selection.empty? && !Sketchup.active_model.selection.to_a.any?{|c| VBO::ShapeForge::Identify.profile_member?(c)}  && last
				if UI.messagebox("Apply profile #{last.fullname} to current selection ?", MB_YESNO) == IDYES
					Sketchup.active_model.start_operation("VBO ShapeForge - Apply #{last.fullname}", true, false, false)

					sel = Sketchup.active_model.selection.to_a
					group = sel[0].parent.entities.add_group(sel)
					build_from_ents(last, [group], nil)
					if @options.delete_edges
						group.erase!
					else
						group.explode
					end
					Sketchup.active_model.commit_operation
				end
			end
			@p_tool = PTool.new
			Sketchup.active_model.tools.push_tool @p_tool
		end
		def self.magic
			last = load_last_profile
			@options = Options.new if @options.nil?
			# Sketchup.active_model.selection.clear
			@p_tool = PTool.new
			Sketchup.active_model.tools.push_tool @p_tool
		end
		def self.profile_dialog_visible?
			VBO::ShapeForge.profile_dialog && VBO::ShapeForge.profile_dialog.visible?
		end

		def self.is_number?(st)
			true if Float(st) rescue false
		end

		def self.assembly_dialog_visible?
			VBO::ShapeForge.assembly_dialog && VBO::ShapeForge.assembly_dialog.visible?
		end

		def self.save_out(ar)
			if ar.is_a?(Array)
				b = []
				ar.each{|c|
					if c.class == Geom::Point3d || c.class == Geom::Vector3d
						b << c.to_a.map{|v| v.round(10)}
					elsif c.class == Geom::Transformation
						b << c.to_a.map{|v| v.round(10)}
					elsif c.class == VBO::ShapeForge::Shape || c.class == VBO::ShapeForge::Post || c.class == VBO::ShapeForge::Rail
						b << c.to_s
					elsif c.class == VBO::ShapeForge::ForgeStructure || c.class == VBO::ShapeForge::Span
						b << c.to_s
					elsif c.class == VBO::ShapeForge::Chain
						b << save_out(c.path)
					elsif c.class == Hash
						b << c.keys.map{|e| save_out([e, c[e]])}.to_h
					elsif c.class == Array
						b << save_out(c)
					elsif c.class == String && is_number?(c)
						b << c.to_f
					elsif c.class.to_s.include?("Curve")
						b << [c.persistent_id, c.vertices.map{|v| v.position.to_a}]
					elsif c.class == Geom::BoundingBox
						b << (0..7).to_a.map{|e| c.corner(e).to_a}
					elsif c.class == Sketchup::ComponentDefinition
						b << c.guid
					elsif c.class == Sketchup::Group
						b << c.persistent_id
					elsif c.class == Sketchup::ComponentInstance
						b << c.persistent_id
					elsif c.class == Sketchup::Vertex
						b << [c.persistent_id, c.position.to_a]
					elsif c.class == Sketchup::Edge
						b << [c.persistent_id, [c.start.position.to_a,c.end.position.to_a]]
					elsif c.class == Sketchup::Text
						b << c.text
					elsif c.class == Sketchup::Entities
						b << nil
					elsif !c
						b << c
					else
						b << c
					end
				}
				b
			else
				ar
			end
		end
    def self.load_component(url)
      model = Sketchup.active_model


      loadmodel = "https://system.sketchupthai.com/samrtobj/obj/"+url+'.skp'
      #loadmodel = "https://sketchuphome.com/smart%20object/obj/"+ url + ".skp"

      loads = model.definitions.load_from_url(loadmodel)
      te = model.place_component(loads)
    end
		def self.load_file_form_web(id)
      # require 'open-uri'
      # url = "https://system.sketchupthai.com/samrtobj/obj/#{id}.skp"

      # download_path = File.join(File.dirname(__FILE__), 'product', 'profile.skp')

      # if File.exist?(download_path)
      #   puts "Deleting existing file"
      #   FileUtils.rm(download_path)
      # end

      # # ดาวน์โหลดไฟล์ SKP จาก URL
      # URI.open(url) do |skp_file|
      #   # อ่านไฟล์ SKP เป็น binary
      #   skp_data = skp_file.read

      #   # บันทึกไฟล์ SKP ลงในเครื่อง
      #   File.open(download_path, 'wb') do |file|
      #       file.write(skp_data)
      #   end
      #   end

      # return download_path
			model = Sketchup.active_model
      loadmodel = "https://system.sketchupthai.com/samrtobj/obj/"+id+'.skp'
      #loadmodel = "https://sketchuphome.com/smart%20object/obj/"+ url + ".skp"

      model.definitions.load_from_url(loadmodel)
    end
		def self.show_smart_object_dialog
			if @smart_object
        @smart_object.close
        @smart_object = nil
        return
      end

      @smart_object = UI::HtmlDialog.new(
        dialog_title:  "Smart Objects",
        scrollable: true,
        height: 600,
        width: 800,
        left: 200,
        top: 200,
        resizable: true,
        preferences_key: "shape.fun.connect"
      )
      @smart_object.set_on_closed(){
        @smart_object = nil
      }
      @smart_object.add_action_callback("ready"){|add_action_callback |
				# Try to install viewport overlay for Assembly Edit toggle
				VBO::ShapeForge.ensure_ass_edit_overlay
				# Only inject the in-page DOM overlay if the viewport overlay isn't available
				unless VBO::ShapeForge.ass_edit_overlay_installed?
				@smart_object.execute_script(<<~JS
          function hideElementsByClass(className) {
            const elements = document.querySelectorAll(`.${className}`);
            elements.forEach(element => {
                element.style.display = 'none';
            });
          }
          function applyCssToClass(className, cssStyles) {
            const elements = document.querySelectorAll(`.${className}`);
            elements.forEach(element => {
              for (let [property, value] of Object.entries(cssStyles)) {
                element.style.setProperty(property, value, 'important');
              }
            });
          }
          function resetCssByClass(className) {
              const elements = document.querySelectorAll(`.${className}`);
              elements.forEach(element => {
                  element.removeAttribute('style');
              });
          }
          function applyHoverEffect(className, hoverStyle, releaseStyle = {}) {
            const elements = document.querySelectorAll(`.${className}`);
            elements.forEach(element => {
                element.addEventListener('mouseover', () => {
                    Object.assign(element.style, hoverStyle);
                });
                element.addEventListener('mouseout', () => {
                  Object.assign(element.style, releaseStyle);
                });
            });
          }

          document.addEventListener("contextmenu", function(event) {
            //event.preventDefault();
          });

          hideElementsByClass('col-sm-auto');
            applyCssToClass(
              'col-sm-auto',
              {
                'width' : '0px',
              }
            );
            applyCssToClass(
              'col-sm p-3 min-vh-100',
              {
                'padding' : '8px',
              }
            );
            applyCssToClass(
              'container',
              {
                'max-width': 'none',
              }
            );
            resetCssByClass('card');
            resetCssByClass('rounded');
            //resetCssByClass('shadow');


            applyCssToClass(
              'card-image',
              {
                'padding' : '18px',
                'border-radius' : '4px',
              }
            );
            applyCssToClass(
              'card-body',
              {
                'padding' : '0',
              }
            );
            applyCssToClass(
              'h6',
              {
                'font-size' : '14px',
              }
            );
            applyHoverEffect('card-image', {
              border: '1px solid #4197c5'
            }, {
              border: 'none'
            });
						applyCssToClass(
							'card',
							{
								'border' : 'none',
								'box-shadow' : 'none',
							}
						);

						// Insert "Edit Path" toggle button into the header toolbar (left of Favorites)
						(function(){
							function ensureButton(){
								var tabs = document.querySelector('.tool-tabs');
								if(!tabs){ return false; }
								var fav = document.getElementById('btnFavorites');
								if(!fav){ return false; }
								var btn = document.getElementById('btnEditPathAss');
								if(!btn){
									btn = document.createElement('button');
									btn.id = 'btnEditPathAss';
									btn.className = 'tool-tab';
									btn.innerHTML = '<span class="tool-icon">✏️</span><span>Edit Path</span>';
									btn.title = 'เปิด/ปิดโหมดแก้ไขเส้นทาง Assembly';
									btn.addEventListener('click', function(){
										var enabled = !btn.classList.contains('active');
										btn.classList.toggle('active', enabled);
										if (window.sketchup && typeof sketchup.ass_click_edit === 'function') {
											sketchup.ass_click_edit(enabled);
										}
									});
									tabs.insertBefore(btn, fav);
								}
								return true;
							}

							// Allow Ruby to push current state to the button
							window.__applyAssClickEditState = function(state){
								var btn = document.getElementById('btnEditPathAss');
								if(!btn) return;
								var enabled = (state === true) || (state === 'true');
								btn.classList.toggle('active', !!enabled);
							};

							// Try create button now and also after a short delay (in case DOM not ready)
							if(!ensureButton()){
								setTimeout(ensureButton, 300);
								setTimeout(ensureButton, 800);
							}

							// Ask Ruby for current state to reflect initial toggle UI
							if (window.sketchup && typeof sketchup.ass_click_edit_state === 'function'){
								sketchup.ass_click_edit_state();
							}
						})();
          JS
        )
					end
      }
			# Assembly Click-Edit toggle handler from Smart Object dialog
			@smart_object.add_action_callback("ass_click_edit") { |action_context, enabled|
				options = VBO::ShapeForge::OptionsForgeStructure.new
				options.click_edit = !!enabled
				if options.click_edit
					VBO::ShapeForge.enable_click_edit_ass_observer
				else
					VBO::ShapeForge.disable_click_edit_ass_observer
				end
				options.save
			}
					# Query current Assembly Click-Edit state
					@smart_object.add_action_callback("ass_click_edit_state") { |action_context|
						options = VBO::ShapeForge::OptionsForgeStructure.new
						state = options.click_edit ? 'true' : 'false'
						# Respond to the webview to update its toggle UI if handler exists
						@smart_object.execute_script("if (window.__applyAssClickEditState) { window.__applyAssClickEditState(#{state}); }")
					}
					# Generic edit mode setter for index-material.php
					@smart_object.add_action_callback("set_edit_mode") { |action_context, enabled|
						enabled_bool = (enabled.to_s == 'true') || (enabled == true)
						options = VBO::ShapeForge::OptionsForgeStructure.new
						options.click_edit = enabled_bool
						if enabled_bool
							VBO::ShapeForge.enable_click_edit_ass_observer
						else
							VBO::ShapeForge.disable_click_edit_ass_observer
						end
						options.save
					}
      @smart_object.add_action_callback("loadmodel") { |action_context, id, mode|
			pm_skuc = defined?(VBO::ShapeForge) ? VBO::ShapeForge : nil
				# pm_toolbox = defined?(Toolbox::VBO::ShapeForge) ? Toolbox::VBO::ShapeForge : nil
				# UI.messagebox mode
			begin
				if mode == "assembly"
					# Load assembly definition and start placement tool
					model = Sketchup.active_model
					loads = load_file_form_web(id)
					if loads
						read_ass = VBO::ShapeForge::ForgeStructure.read(loads)
						ass = VBO::ShapeForge::AssDraw.new(read_ass)
						tool = VBO::ShapeForge::PlineTool.new(ass)
						tool.action = ->(t){ }
						tool.snap = ->(view, tool){
							pos = tool.instance_variable_get(:@pos)
							path = tool.instance_variable_get(:@path)
							return[nil, nil, nil] if pos.nil? ||  pos[0] == 0 || path.nil?
							tr = Sketchup::InstancePath.new(path).transformation
							member_group = path.find{|m| VBO::ShapeForge::Identify.profile_member?(m)}
							ass_group = path.find{|m| VBO::ShapeForge::Identify.assembly?(m)}
							snap_point = nil
							chain = nil
							mem = nil
							if ass_group
								ass = VBO::ShapeForge::ForgeStructure.get(ass_group)
								chain = ass.chain.map{|c| c.transform(tr)}
								point = [pos[1].x, pos[1].y, 0]
								snap_point = chain.find{|c| view.screen_coords(c).distance(point) < 10 * UI.scale_factor}
								mem = ass
							end
							if member_group && !snap_point
								member = VBO::ShapeForge::ForgeElement.new(member_group)
								chain = member.chain.path.map{|c| c.transform(tr)}
								point = [pos[1].x, pos[1].y, 0]
								snap_point = chain.find{|c| view.screen_coords(c).distance(point) < 10 * UI.scale_factor}
								mem = member
							end
							[snap_point, chain, mem]
						}
						model.tools.push_tool tool
						# Notify webview success
						@smart_object&.execute_script("if (window.__onModelLoaded) window.__onModelLoaded('assembly', #{id.inspect});")
					else
						raise "Load failed"
					end
				else
					# Profile/component mode
					load_component(id)
					@smart_object&.execute_script("if (window.__onModelLoaded) window.__onModelLoaded('component', #{id.inspect});")
				end
			rescue => e
				msg = e.message.to_s
				@smart_object&.execute_script("if (window.__onModelLoadError) window.__onModelLoadError(#{msg.inspect});")
			end
			}
      @smart_object.set_url"https://system.sketchupthai.com/samrtobj/smart-object-mvp_updated.php"
      #@smart_object.set_url"https://system.sketchupthai.com/samrtobj/index-material.php"
      #@smart_object.set_url"https://sketchuphome.com/smart%20object/"
      # @smart_object.set_url"https://system.sketchupthai.com/samrtobj/index.php?mode=Profile"
      @smart_object.set_position(100, 50)
      @smart_object.show
    end

		module FixSolid
			def self.fix_solid(ents, recursive = true)

				tra = Geom::Transformation.new
				temp_pt = Geom::Point3d.new(3.14, 1.59, 2.65)

				# Remove overlapping/duplicate faces.
				to_remove = []
				ents.grep(Sketchup::Edge).each { |e|
				next unless e.valid?
				e.faces.each { |f1|
					next unless f1.valid?
					e.faces.each { |f2|
						next unless f2.valid?
						next if f1 == f2
						next unless f1.normal.parallel?(f2.normal)
						next if to_remove.include?(f1) or to_remove.include?(f2)
						v1 = f1.outer_loop.vertices
						v2 = f2.outer_loop.vertices
						if (v1 - v2).empty? && (v2 - v1).empty?
							to_remove << f2
						end
					}
				}
				}
				to_remove.each { |e|
					next unless e.valid?
					e.erase!
				}
				# Add faces at desired locations.
				size = ents.to_a.size
				e_a = ents.to_a
				ents.grep(Sketchup::Edge).each { |e|
					e.find_faces if e.valid? && e.faces.size == 1
				}
				# Sometimes added faces appear inside solids; remove them.
				e_a[size..-1].each { |face|
					next unless face.is_a?(Sketchup::Face)
					face.edges.each { |edge|
						if edge.valid? && edge.faces.size > 2
							to_remove << face
							break
						end
					}
				}
				to_remove.each { |e| e.erase! if e.valid? }
				# Sometimes added faces intersect entities in between; remove them.
				# Not implemented yet.
				# Remove internal faces.
				# This removes faces with all face edges having three faces.
				# In other words, this removes most faces inside solids.
				ents.grep(Sketchup::Face).each { |e|
					next unless e.valid?
					remove = true
					e.edges.each { |edge|
						next if edge.faces.size > 2
						remove = false
						break
					}
					to_remove << e if remove
				}
				to_remove.each { |e|
					next unless e.valid?
					edges = e.edges
					e.erase!
					ents.add(edges) if ents.is_a?(Sketchup::Selection)
				}
				# Remove unused edges.
				# Removes all coplanar and single edges.
				2.times {
					ents.grep(Sketchup::Edge).each { |e|
						next unless e.valid?
						if e.faces.empty?
							e.erase!
							next
						end
						next if e.faces.size != 2
						f1, f2 = e.faces
						# Check if faces are coplanar.
						if f1.normal.parallel?(f2.normal) && f1.material == f2.material && f1.back_material == f2.back_material && f1.layer == f2.layer
							# Verify that faces are safe to merge. Faces are safe to merge if they are
							# coplanar. Checking face normal is not always enough. Use technique by
							# ThomThom, which checks if all points lie on plane.
							vertices = f1.vertices + f2.vertices
							plane = Geom.fit_plane_to_points( vertices )
							safe = vertices.all? { |v| v.position.on_plane?(plane) }
							if safe
								e.erase!
							end
						end
					}
				}
				# Repair split edges.
				ents.grep(Sketchup::Edge).each { |e|
					next unless e.valid?
					e.vertices.each { |v|
						next unless v.valid?
						if v.edges.size == 2
							v1 = v.edges[0].line[1]
							v2 = v.edges[1].line[1]
							if v1.parallel?(v2)
								to_remove << ents.add_line(v.position, temp_pt)
							end
						end
					}
				}
				to_remove.each { |e|
					next unless e.valid?
					e.erase!
				}
				# Repair curves.
				repaired = {}
				ents.grep(Sketchup::Edge).each { |e|
					next unless e.valid?
					next unless e.curve
					e.vertices.each { |v|
						next unless v.valid?
						# Determine if current vertex edges contains a broken curve.
						found = false
						v.edges.each { |edge|
							next unless edge.valid?
							next unless edge.curve
							next if edge == e || edge.curve.edges.include?(e)
							next if edge.faces.size != e.faces.size
							found = true
							break
						}
						next unless found
						# Soften surrounding edges if the curve exists.
						v.edges.each { |edge|
							next unless edge.valid?
							if edge.curve
								repaired[edge.curve] = edge.curve.edges.size
								next
							end
							edge.soft = true
							edge.smooth = true
						}
						# Attempt to combine curve by adding a temporary edge and deleting.
						ents.add_line(v.position, temp_pt).erase!
					}
					# We don't need a curve if it consists of one edge.
					e.explode_curve if e.curve.count_edges == 1
				}
				return unless recursive
				ents.grep(Sketchup::Group).each { |e| fix_solid(e.entities, true) }

				processed_definitions = []
				ents.grep(Sketchup::ComponentInstance).each { |e|
					next if processed_definitions.include?(e.definition)
					processed_definitions << e.definition
					fix_solid(e.definition.entities, true)
				}
			end
		end

		class SolidShell
			PI2 = Math::PI * 2
			attr_reader :internal_faces, :external_faces, :reversed_faces
			# @param [Sketchup::Entities] entities
			def initialize(entities)
				@entities = entities
				@shell_faces = nil
				@internal_faces = nil
				@external_faces = nil
				@reversed_faces = nil
			end

			def resolve
				@shell_faces = Set.new
				@internal_faces = Set.new
				@external_faces = Set.new
				@reversed_faces = Set.new

				shell_front = Set.new
				find_geometry_groups(@entities) { |geometry_group|
					start_face = find_start_face(geometry_group, true)
					next if start_face.nil?
					shell_front.merge(find_shell(start_face))
				}

				faces = @entities.grep(Sketchup::Face)
				@internal_faces = Set.new(faces).subtract(shell_front)

				temp_reversed_faces = @reversed_faces.dup

				shell_back = Set.new
				find_geometry_groups(@entities) { |geometry_group|
					start_face = find_start_face(geometry_group, false)
					next if start_face.nil?
					shell_back.merge(find_shell(start_face))
				}

				@shell_faces = shell_front.intersection(shell_back)

				@external_faces = Set.new(faces).subtract(@internal_faces)
												.subtract(@shell_faces)

				@reversed_faces = @shell_faces.intersection(temp_reversed_faces)
				nil
			end


			def valid?
				if @shell_faces.nil?
					raise RuntimeError, "`resolve` must be called before calling `valid?`"
				end
				@shell_faces.size > 0 && @shell_faces.all? { |face|
					face.edges.all? { |edge|
						faces = edge.faces.select { |f| @shell_faces.include?(f) }
						faces.size > 1
					}
				}
			end

			private

			def find_geometry_groups(entities)
				num_groups = 0
				stack = entities.to_a
				until stack.empty?
					entity = stack.pop
					next unless entity.respond_to?(:all_connected)
					num_groups += 1
					geometry_group = entity.all_connected
					yield(geometry_group)
					stack = stack - geometry_group
				end
				num_groups
			end


			def get_faces(entity)
				entity.faces.reject { |face| @internal_faces.include?(face) }
			end

			def face_normal(face)
				normal = face.normal
				if @reversed_faces.include?(face)
					normal.reverse!
				end
				normal
			end

			def edge_reversed_in?(edge, face)
				reversed = edge.reversed_in?(face)
				if @reversed_faces.include?(face)
					reversed = !reversed
				end
				reversed
			end

			def reverse_face(face)
				if @reversed_faces.include?(face)
					@reversed_faces.delete(face)
				else
					@reversed_faces << face
				end
				face
			end

			def find_start_face(entities, outside)

				vertices = Set.new
				entities.grep(Sketchup::Edge) { |edge|
				vertices.merge(edge.vertices)
				}
				vertices.delete_if { |vertex| get_faces(vertex).empty? }
				return nil if vertices.empty?

				max_z_vertex = vertices.max { |a, b|
				a.position.z <=> b.position.z
				}

				edges = max_z_vertex.edges.delete_if { |edge| get_faces(edge).empty? }
				edge = edges.min { |a, b|

				val_a = edge_normal_z_component(a)
				val_b = edge_normal_z_component(b)
				result = val_a <=> val_b
				if result.nil?
					klass_a = val_a.class.name
					klass_b = val_b.class.name
					raise HeisenBug, "A: #{a.line.inspect} (#{val_a.inspect}) #{klass_a} - B: #{b.line.inspect} (#{val_b.inspect}) #{klass_b}"
				end
				result
				}

				face = get_faces(edge).max { |a, b|
				face_normal(a).z.abs <=> face_normal(b).z.abs
				}

				if outside
				reverse_face(face) if face_normal(face).z < 0
				else
				reverse_face(face) if face_normal(face).z > 0
				end

				face
			end

			def edge_normal_z_component(edge)
				edge.line[1].z.abs
			end


			def edge_vector(edge, face)
				if edge_reversed_in?(edge, face)
				edge.end.position.vector_to(edge.start)
				else
				edge.start.position.vector_to(edge.end)
				end
			end

			def get_other_face(edge, face)
				other_face = get_faces(edge).find { |edge_face| edge_face != face }
				return nil if other_face.nil? # Edge connected to same face.
				if edge_reversed_in?(edge, face) == edge_reversed_in?(edge, other_face)
				reverse_face(other_face)
				end
				other_face
			end

			def find_other_shell_face(edge, face)
				return nil if get_faces(edge).size == 1

				return get_other_face(edge, face) if get_faces(edge).size == 2

				return nil if get_faces(edge).count(face) > 1

				edge_direction = edge_vector(edge, face)
				face_direction = face_normal(face)
				product = face_direction.cross(edge_direction)
				reversed = edge_reversed_in?(edge, face)

				minimum_angle = PI2
				shell_face = nil

				get_faces(edge).each { |other_face|
				next if other_face == face

				other_face_direction = face_normal(other_face)
				if edge_reversed_in?(edge, other_face) == reversed
					other_face_direction.reverse!
				end

				other_product = edge_direction.cross(other_face_direction)

				angle = product.angle_between(other_product)
				if other_product.dot(face_direction) < 0
					angle = PI2 - angle
				end

				if angle < minimum_angle
					minimum_angle = angle
					shell_face = other_face
				end
				}

				return nil if shell_face.nil?

				if edge_reversed_in?(edge, shell_face) == reversed
				reverse_face(shell_face)
				end

				shell_face
			end

			def find_shell(start_face)
				stack = []
				processed = Set.new
				shell = Set.new

				stack << start_face
				processed << start_face

				until stack.empty? do

				face = stack.pop
				shell << face

				face.loops.each { |loop|
					loop.edges.each { |edge|
					next if processed.include?(edge) || get_faces(edge).size < 2

					processed << edge
					other_shell_face = find_other_shell_face(edge, face)

					next if other_shell_face.nil?
					next if processed.include?(other_shell_face)

					stack << other_shell_face
					processed << other_shell_face
					}
				}
				end

				shell.to_a
			end


		end

	end
end
