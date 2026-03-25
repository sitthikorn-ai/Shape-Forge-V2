Sketchup.require File.join(File.dirname(__FILE__), 'dialog')
# Sketchup.require File.join(File.dirname(__FILE__), 'assembly_controller')
Sketchup.require File.join(File.dirname(__FILE__), 'options')
Sketchup.require File.join(File.dirname(__FILE__), 'fences')
Sketchup.require File.join(File.dirname(__FILE__), 'methods')
Sketchup.require File.join(File.dirname(__FILE__), 'main')
Sketchup.require File.join(File.dirname(__FILE__), 'posts_n_rails')
Sketchup.require File.join(File.dirname(__FILE__), 'member')

module VBO::ShapeForge
	module Classify
			def self.profile_member?(ent)

				dicts=nil
				defn_dicts=nil
				has_profile=false

				if ent.kind_of?(Sketchup::Group)
					dicts=ent.attribute_dictionaries #version 1.0 backward compatible
					defn_dicts=ent.entities.parent.attribute_dictionaries  #version 2.0
				elsif ent.kind_of?(Sketchup::ComponentInstance)
					defn_dicts=ent.definition.attribute_dictionaries #version 2.0
				end

				if dicts
					if dicts["ProfileBuilder"] and dicts["ProfileBuilder"]["profile"]
						has_profile=true
					end
				end

				if defn_dicts
					if defn_dicts["ProfileBuilder"] and defn_dicts["ProfileBuilder"]["profile"]
						has_profile=true
					end
				end

				return has_profile

			end


			def self.assembly?(ent)

				if  ent.respond_to?(:definition)
					defn=ent.definition
				else
					defn=ent
				end
				return defn.get_attribute("PBFence","is_fence") || defn.get_attribute("PBFence","is_fence_v2")
			end

			def self.assembly_span?(ent)
				if ent.respond_to?(:definition) && ent.definition.attribute_dictionaries[""]
					ent.definition.attribute_dictionaries[""].keys.find{|c| c.start_with?('Span')}
				else
					false
				end
			end

			def self.assembly_rail?(ent)
				return if assembly_span?(ent)
				if profile_member?(ent) && ent.definition.attribute_dictionaries[""]
					ent.definition.attribute_dictionaries[""].keys.find{|c| c.start_with?('Rail')}
				end
			end

			def self.assembly_post?(ent)
				return if assembly_span?(ent)
				if  ent.respond_to?(:definition) && ent.definition.attribute_dictionaries[""]
					ent.definition.attribute_dictionaries[""].keys.find{|c| c.start_with?('Post')}
				end
			end

		end #end module classify
	#
	class ForgeStructure
		include Geometry
		attr_accessor :name, :group, :fence
		private_class_method :new
		@@dict="PBFence"
		@@path=[]

		def ForgeStructure.add(ents)
			@group = ents.add_group()
			assembly = new(@group)
			assembly
		end

		def ForgeStructure.create_in(defn)
			assembly = new(defn)
			assembly
		end

		def ForgeStructure.read(ent)
      # puts "ForgeStructure.read #{ent.class}"
			if ent.is_a?(Hash) ||
        ent.is_a?(String)  ||
        (ent.respond_to?(:definition) && VBO::ShapeForge::Classify.assembly?(ent)) ||
        ent.is_a?(VBO::ShapeForge::ForgeStructure) ||
        (ent.is_a?(Sketchup::ComponentDefinition) && ent.get_attribute("PBFence","is_fence"))
				a = new(ent)
			else
				a = nil
			end
			a
		end

		def ForgeStructure.get(ent)
			if VBO::ShapeForge::Classify.assembly?(ent)
				a = new(ent)
			else
				a = nil
			end
		return a
		end

		def [](key)
			@fence[key]
		end


		def initialize(object)
			if object.class==Sketchup::ComponentInstance
				@group = object
				@su_defn=object.definition
				@instance=object
				@fence=Fence.new
				load_fence
				@name = @fence.name
			elsif object.class==Sketchup::Group
				@group = object
				@su_defn=object.definition
				@instance=object
				@fence=Fence.new
				load_fence
				@name = @fence.name
			elsif object.class==Sketchup::ComponentDefinition
				@su_defn=object
				@instance=object.instances[0]
				@fence=Fence.new
				load_fence
				@name = @fence.name
			elsif object.class==Hash
				@su_defn = nil
				@fence=Fence.new
				@fence.load_from_object(object)
				@name = @fence.name
			elsif object.class==String
				@su_defn = nil
				@fence=Fence.new
				@fence.load_from_string(object)
				@name = @fence.name
			elsif object.class==VBO::ShapeForge::ForgeStructure
				@su_defn = nil
				@fence = object.fence
				@name = @fence.name
			end
			@name = "A##{SecureRandom.urlsafe_base64(6).gsub(/[^a-zA-Z0-9]/, '')}" if @name.to_s.empty?
			@fence.name = @name
		end


		def transformation
			# Return nil if group/instance is deleted
			return nil if !@instance || (@instance.respond_to?(:valid?) && !@instance.valid?)
			@instance.transformation
		end

		def draw(full = false)
			@ents = @su_defn.entities
			@ents.clear!
			pts=self.chain
			@fence.calc_posts_layout(pts)
			build_posts(full)
			build_rails(full)
			h = @ents.to_a.group_by{|o| "#{o.definition.persistent_id}#{o.transformation.origin.to_a}"}

			# Erase duplicates (v 1.2.5 - 231112 - Added by Tiger)
			erase = []
			h.each{|k,v|
				if v.length > 1
					erase += v[1..-1]
				end
			}
			@ents.erase_entities(erase)

			save_fence_properties_to_defn()
			@group.name = @fence.name
			@group
		end

		def clear_attr(defi, type)
			at = defi.attribute_dictionaries.find{|c|
				c.keys.any?{|k| k.start_with?(type)}
			}
			if at
				at.each_key{|key| at.delete_key(key) if key.start_with?(type)}
			end
		end


		def build_posts(full = false)
			# puts "build_posts"
			posts = @fence.posts
			posts.find_all{|post|
				post.valid? && (post.enabled || full)
			}.each{|post|

				temp_trans = post.instances.values.flatten
				# add posts
				post.instances.each {|edge,transformations|
					trs = transformations.sort_by{|c| c.origin.distance(edge[0])}
					trs.each_with_index {|trans, i|
						tr = temp_trans.find{|c| c.origin.to_a == trans.origin.to_a && c.to_a != trans.to_a}
						if tr
							case post.at_junction
							when "Before"
								final_trans = trans
							when "After"
								final_trans = tr
							when "Rotate"
								angle = clock_wise_angle(trans.xaxis,tr.xaxis)
								rot = Geom::Transformation.rotation(trans.origin, trans.zaxis, angle * 0.5)
								final_trans = rot * trans
							when "None"
								final_trans = nil?
							end
							if final_trans
								inst = @ents.add_instance(post.component_definition, final_trans)
								inst.layer = Sketchup.active_model.layers.add(post.layer_name)
								post_index = posts.index(post)
								clear_attr(inst.definition, "Post")
								inst.definition.set_attribute(@dict,"Post#{post_index}",post.to_s)
								inst.set_attribute('','@UiId', post.ui_id)
							end
							temp_trans -= [trans, tr]
						elsif temp_trans.include?(trans)
							is_start = edge[0] == chain[0] && post.at_start? && i == 0
							is_end = edge[1] == chain[-1] && post.at_end? &&  i == trs.length - 1
							if is_start || is_end || (
								post.at_infill? && (
									edge[0] == chain[0] && i != 0 ||
									edge[1] == chain[-1] && i != trs.length - 1 ||
									edge[0] != chain[0] && edge[1] != chain[-1]
								)

							)
								inst = @ents.add_instance(post.component_definition,trans)
								inst.layer = Sketchup.active_model.layers.add(post.layer_name)
								post_index = posts.index(post)
								clear_attr(inst.definition, "Post")
								inst.definition.set_attribute(@dict,"Post#{post_index}",post.to_s)
								inst.set_attribute('','@UiId', post.ui_id)
							end
							temp_trans -= [trans]
						end
					}
				}

				# add spans
				# junctionsx = ([0] + @fence.calculate_junction_indices(post.junction_angle.degrees, post.spacing)).uniq.map{|i| self.chain[i]}
				junctionsx = ([0] + post.cal_junctions).uniq.map{|i| self.chain[i]}

				# puts "junctions: #{ @fence.calculate_junction_indices_hash(post.junction_angle.degrees, post.spacing)}"


				junctions = post.offset_chain(VBO::ShapeForge::Chain.new(junctionsx), post.use_global_up_offset).to_a.each_cons(2).to_a

				divide = {}
				i = 0
				post.instances.each{|edge, trans|
					j = divide[junctions[i]]
					s = trans#.map{|c| c.origin}
					if j
						divide[junctions[i]] += s.sort_by{|c| c.origin.distance(j[-1].origin)}
					else
						divide[junctions[i]] = s.sort_by{|c| c.origin.distance(edge[0])}
					end

					# split at junction if
					# 1.  edge[-1].to_a == junctions[i][-1].to_a means

					i += 1 if edge[-1].to_a.distance(junctions[i][-1].to_a) < 0.001
				}#.flatten.uniq{|c| c.to_a.map{|d| d.round(3)}}


				divide = divide.map{|k,v|
					[
						k,
						v.each_cons(2).to_a.reject{|x|
							x[0].origin.distance(x[1].origin) < 0.001
						}
					]
				}.to_h
				# puts "divide: #{divide.map{|k,v| [k,v.map{|c| c.map{|d| d.origin}}]}.to_h}"


				spans = @fence.spans
				juncs = []
				divide.each{|edge,sub_divs|
					a_vec = edge[0].vector_to(edge[1])
					x_vec = a_vec.cross(Z_AXIS)
					y_vec = x_vec.cross(a_vec)

					trans_back = ->(point){
						po = point.clone
						if post.x_offset.abs  > 0.001
							po.offset!(x_vec, -post.x_offset)
						end
						if post.y_offset.abs > 0.001
							po.offset!(y_vec, -post.y_offset)
						end
						po
					}

					juncs << [edge[0].to_a]

					sub_divs.each_with_index{|sub_div, i|

						next if sub_div[0].origin.distance(sub_div[1].origin) < 0.001
						sud = sub_div.map{|c| trans_back.call(c.origin)}
						if sud[0].distance(juncs[-1][-1]) > 0.001 && juncs[-1][-1] != chain[0]
							juncs[-1] << sud[0].to_a
							juncs << [sud[1].to_a]
						else
							juncs[-1] = [sud[1].to_a]
						end


						@fence.post_spans(post).find_all{|span|
							span.valid? && (span.enabled || full)
						}.each{|span|
							case span.pattern
							when 0, "|-|-|-|-|"
							when 1, "|-| |-| |"
								next if i % 2 != 0
							when 2, "| |-| |-|"
								next if (sub_divs.length - i) % 2 != 0
							when 3, "|-| | |-|"
								next if i != 0 && i != sub_divs.length - 1
							end
							span_index = spans.index(span)

							create_span(@ents, post, span, span_index, sub_div)
						}
					}
					# juncs[-1] << edge[1]
					if edge[1].distance(juncs[-1][-1]) > 0.001 && edge[1] != chain[-1]
						juncs[-1] << edge[1].to_a
					else
						juncs.pop
					end
				}
				#	cross junctions
				# puts "juncs: #{juncs}"
				if !juncs.empty?
					# juncs << juncs[0] if @fence.chain.closed_path?
					xx =  merge_edges_to_polylines(juncs)
					# puts "xx: #{xx}"
					xx.each{|junc|
						@fence.post_spans(post).each{|span|
							next if !span.valid? || (!span.enabled && full) || !span.cross_junctions || junc.length < 2
							create_span(@ents, post, span, spans.index(span), post.offset_chain(Chain.new(junc), post.use_global_up_offset).to_a)
						}
					}
				end
			}
		end

		def merge_edges_to_polylines(edges)
			edges = edges.map{|edge| edge.uniq{|c| c.to_a.map{|d| d.round(3)}}}.find_all{|edge| edge.length > 1}
			polylines = edges.find_all{|c|
				c.length > 2
			}
			edges = edges - polylines
			vertices = Hash.new(0)
			edges.each{|edge|
				vertices[edge[0].to_a] += 1
				vertices[edge[1].to_a] += 1
			}
			while vertices.length > 0
				st = vertices.keys.find{|k| vertices[k] == 1}

				if st.nil?
					st = vertices.keys.find{|k| vertices[k] == 2}
				end
				if st
					polylines << [st]
					edge = edges.find{|e| e.include?(st)}
					while edge
						po = edge.find{|v| v != st}
						polylines[-1] << po.to_a if polylines[-1][-1].to_a != po.to_a
						vertices[st] -= 1
						vertices[po] -= 1
						vertices.delete(st) if vertices[st] < 1
						vertices.delete(po) if vertices[po] < 1
						edges.delete_if{|e| e.include?(st) && e.include?(po)}
						st = po
						edge = edges.find{|e| e.include?(st)}
					end
					vertices.delete(st)
				else
					break
				end
			end
			polylines.delete_if{|x| x.any?{|y| y.empty? || !y}}
			polylines.map{|x| x.map{|y| Geom::Point3d.new(y)}}
		end

		def create_span(ents, post, span, span_index, sub_div_trans)
			if sub_div_trans[0].is_a?(Geom::Point3d)
				sub_div = sub_div_trans
			else
				sub_div = sub_div_trans.map{|c| c.origin}
			end
			# puts "Subdiv#{sub_div} \nafter simplify: #{simplify_polyline(sub_div)}"
			sub_div = simplify_polyline(sub_div)
			return if sub_div.length < 2
			case span.type
			when 0, "Profile", 2, "Sub Assembly"
				if sub_div.length == 2
					if sub_div[1].z != sub_div[0].z && span.auto_trim && false
						p1,p2 = sub_div.map{|c| c.project_to_plane(ORIGIN, Z_AXIS)}
						span_chain = Chain.new([p1,p2])
					else
						if span.allow_slope
							span_chain = Chain.new(sub_div)
						else
							p1,p2 = sub_div.map{|c| c.project_to_plane(sub_div[0], Z_AXIS)}
							span_chain = Chain.new([p1,p2])
						end
					end
				else
					span_chain = Chain.new(sub_div)
				end

				span_chain = span.offset_chain(span_chain, span.use_global_up_offset)
				span_pts = span_chain.path
				span_pts = simplify_polyline(span_pts)
				return if span_pts.length < 2

				if span.start_setback != 0.0
					return if span_pts[0].distance(span_pts[1]) < 0.001
					span_pts[0] = span_pts[0].offset(span_pts[0].vector_to(span_pts[1]), span.start_setback)
				end
				if span.end_setback != 0.0
					return if span_pts[-1].distance(span_pts[-2]) < 0.001
					span_pts[-1] = span_pts[-1].offset(span_pts[-1].vector_to(span_pts[-2]), span.end_setback)
				end

				if span.sag.abs > 0.0001 && span.sag_divisions > 1
					# UI.messagebox span.sag.to_l.to_s
					span_pts = span_pts.each_cons(2).uniq.map{|p1,p2|
						p3 = middle_point(p1,p2).offset(Z_AXIS, - span.sag)
						arc(p1,p2,p3, span.sag_divisions)
					}.flatten(1)
				end

				case span.type
				when 0, "Profile"
					return if span.profile.nil?
					profile = Shape.new(span.profile.to_s)
					pm = VBO::ShapeForge::ForgeElement.add(ents, span_pts)
					pm.set_from_profile!(profile, false)


					pm.draw()

					pm.definition.set_attribute(@dict,"Span#{span_index}",span.to_s)
					span.group = pm.definition.instances[0]
					span.group.layer = Sketchup.active_model.layers.add(span.layer_name)
					span.group.set_attribute('','@UiId', span.ui_id)

				when 2, "Sub Assembly"
					return if span.sub_assembly.nil?
					assembly = VBO::ShapeForge::ForgeStructure.read(span.sub_assembly)
					unless assembly.nil?
						# UI.messagebox "right"
						ass = VBO::ShapeForge::ForgeStructure.add(@su_defn.entities)
						ass.fence = assembly.fence
						ass.set_chain(span_pts)
						group = ass.draw()
						group.definition.set_attribute(@dict,"Span#{span_index}",span.to_s)
						span.group = group
						span.group.layer = Sketchup.active_model.layers.add(span.layer_name)
						span.group.set_attribute('','@UiId', span.ui_id)
					else
						# UI.messagebox "Why????" + assembly.to_s
					end
				end

			when 1, "Component"
				comp = span.component_definition

				return if comp.nil? ||
				!comp.is_a?(Sketchup::ComponentDefinition) ||
				sub_div[0].distance(sub_div[-1]) == 0
				instance = ents.add_instance(comp, Geom::Transformation.new)
				instance.layer = Sketchup.active_model.layers.add(span.layer_name)
				instance.set_attribute('','@UiId', span.ui_id)
				projected_sub_div = sub_div.map{|c| c.project_to_plane(sub_div[0], Z_AXIS)}

				vector = sub_div[0].vector_to(sub_div[-1])
				projected_vector = projected_sub_div[0].vector_to(projected_sub_div[-1])
				if post.stay_vertical
					if projected_vector.length > 0.001
						x_vector =  (projected_vector * Z_AXIS)
						y_vector = (x_vector * projected_vector)
						tr = Geom::Transformation.new(sub_div[0], projected_vector, x_vector.reverse)
					else
						instance.erase!
						return
					end
				else
					if vector.parallel?(Z_AXIS)
						z_axis = sub_div_trans[0].zaxis
						x_axis = sub_div_trans[0].xaxis
						x_vector =	(vector * z_axis)
						y_vector = (x_vector * vector)
						tr = Geom::Transformation.new(sub_div[0], vector, x_vector.reverse)
					else
						x_vector =  (vector * Z_AXIS)
						if span.use_global_up_offset
							y_vector = Z_AXIS.clone
						else
							y_vector = (x_vector * vector)
							y_vector = Z_AXIS.clone if y_vector.length == 0
						end

						tr = Geom::Transformation.new(sub_div[0], vector, x_vector.reverse)
					end
				end

				if span.x_offset != 0.0
					x_vector.length = span.x_offset
					tr = Geom::Transformation.translation(x_vector) * tr
				end
				if span.y_offset != 0.0
					y_vector.length = span.y_offset
					tr = Geom::Transformation.translation(y_vector) * tr
				end

				len_x = comp.bounds.width
				start_setback = span.start_setback
				end_setback = span.end_setback
				width = 0

				ratio = 1
				if sub_div[0].z != sub_div[-1].z

					if post.stay_vertical
						start_vector = vector.clone
						start_vector.length = start_setback
						end_vector = vector.clone.reverse
						end_vector.length = end_setback
						width = projected_sub_div[0].distance(projected_sub_div[-1]) - start_setback - end_setback

						# if span.shear_on_slope && post.stay_vertical
						# 	start_shear_z = start_setback * Math.tan(angle)
						# 	end_shear_z = end_setback * Math.tan(angle)
						# 	ratio = (sub_div[-1].z - sub_div[0].z - (end_shear_z + start_shear_z)) / width
						# 	shear_instance_along(instance,ratio,'z')
						# end
					else
						start_vector = vector.clone
						start_vector.length = start_setback
						end_vector = vector.clone.reverse
						end_vector.length = end_setback
						width = sub_div[0].distance(sub_div[-1]) - start_setback - end_setback
					end
				else
					start_vector = vector.clone
					start_vector.length = start_setback
					end_vector = vector.clone.reverse
					end_vector.length = end_setback

					width = sub_div[0].distance(sub_div[-1]) - start_setback - end_setback
				end


				if start_setback != 0.0
					# puts 'start setback'
					tr = Geom::Transformation.translation(start_vector) * tr
				end

				scale = width / len_x
				tr2 = Geom::Transformation.scaling(scale, 1, 1)
				# scale to fit


				if span.shear_on_slope && post.stay_vertical && sub_div[0].z != sub_div[-1].z
					angle = vector.angle_between(projected_vector)
					start_shear_z = start_setback * Math.tan(angle)
					end_shear_z = end_setback * Math.tan(angle)
					ratio = (sub_div[-1].z - sub_div[0].z - (end_shear_z + start_shear_z)) / width

					a = [
						1, 0, 0, 0,
						0, 1, 0, 0,
						0, 0, 1, 0,
						0, 0, 0, 1
					]

					a[2] = ratio
					tr = tr * Geom::Transformation.new(a)
				end

				if span.scale_to_fit
					tr =  tr * tr2
				end
				instance.transform!(tr)

				comp.set_attribute(@dict,"Span#{span_index}",span.to_s)
			#when 2
				# puts "ForgeStructure Span from #{sub_div[0]} to #{sub_div[1]}}"
				#assembly = VBO::ShapeForge::ForgeStructure.read(span.sub_assembly)
				#puts assembly.fence.posts[0].class
			end
		end

		def entities
			@group.definition.entities
		end

		def to_path(trans = Geom::Transformation.new)
			tr = @group.transformation
			group_ents = self.entities
			edges = group_ents.find_all {|e| e.class == Sketchup::Edge}
			group_ents.erase_entities(edges)
			pts = self.chain
			pts = pts.map{|c| c.transform(trans)}
			self.set_chain(pts)
			group_ents.add_edges(pts)
			rev = group_ents.find_all{|e| !e.is_a?(Sketchup::Edge) && e.respond_to?(:erase!)}
			rev.each{|e| e.erase!}
			tr
		end

		def build_rails(full = false)
			path_pts = self.chain

			rails = @fence.rails
			rails.find_all{|rail|
				rail.valid? && (rail.enabled || full)
			}.each{|rail|
				rail_chain = Chain.new(path_pts)
				profile = Shape.new(rail.profile.to_s)

				rail_chain = rail.offset_chain(rail_chain, rail.use_global_up_offset)
				rail_pts = rail_chain.path
				pm = ForgeElement.add(@ents,rail_pts)
				pm.set_from_profile!(profile, false)
				unless rail_chain.closed_path?
					pm.extend_start(-(rail.start_setback)) if rail.start_setback != 0.0
					pm.extend_end(-(rail.end_setback)) if rail.end_setback != 0.0
				end



				if rail.allow_slope
					vec1 = rail_chain.path[0].vector_to(rail_chain.path[1])
					unless vec1.parallel?(Z_AXIS)
						side_vec = vec1 * Z_AXIS
						no_vec = side_vec * Z_AXIS
						plane1 = [pm.chain[0].transform(pm.transformation),no_vec]
						pm.set_attribute("cap_0_trim", ["plane", pm.chain.path[0].to_a, plane1.map{|c| c.transform(pm.group.transformation.inverse).to_a}])
					end
					vec2 = rail_chain.path[-1].vector_to(rail_chain.path[-2])
					unless vec2.parallel?(Z_AXIS)
						side_vec = vec2 * Z_AXIS
						no_vec = side_vec * Z_AXIS
						plane2 = [pm.chain[-1].transform(pm.transformation),no_vec]
						pm.set_attribute("cap_1_trim", ["plane", pm.chain[-1].to_a, plane2.map{|c| c.transform(pm.transformation.inverse).to_a}])
					end
				end

				pm.draw

				rail_index = rails.index(rail)
				clear_attr(pm.group.definition, "Rail")
				pm.group.set_attribute(@dict,"Rail#{rail_index}",rail.to_s)
				pm.definition.set_attribute(@dict,"Rail#{rail_index}",rail.to_s)
				rail.group = pm.group
				rail.group.set_attribute('','@UiId', rail.ui_id)
			}
		end


		def set_chain(pts,trans=nil)
			trans=Geom::Transformation.new unless trans
			pts=pts.collect {|p| p.transform(trans.inverse).to_a}
			@su_defn.set_attribute(@@dict,'path',pts)
		end

		def chain

			pts = @su_defn.get_attribute(@@dict,'path',@@path)
			pts = pts.collect {|p| Geom::Point3d.new(p)}
			return pts

		end

		def save_fence_properties_to_defn()
			clear_attr(@su_defn, "Post")
			clear_attr(@su_defn, "Rail")
			clear_attr(@su_defn, "Span")
			posts = @fence.posts
			rails = @fence.rails
			spans = @fence.spans

			dicts = @su_defn.attribute_dictionaries
			@su_defn.description = @fence.description
			@su_defn.name = @fence.name

			@su_defn.set_attribute(@@dict,"is_fence",true)
			@su_defn.set_attribute(@@dict,"name",@fence.name)

			posts.each_index {|i|
				@su_defn.set_attribute(@@dict,"Post#{i}",posts[i].to_s)
			}
			rails.each_index {|i|
				@su_defn.set_attribute(@@dict,"Rail#{i}",rails[i].to_s)
			}
			spans.each_index {|i|
				@su_defn.set_attribute(@@dict,"Span#{i}",spans[i].to_s)
			}

		end

		def clear_existing_entities()
			ents=@su_defn.entities
			ents.clear!
		end

		def draw_path()
			clear_existing_entities()
			ents=Sketchup.active_model.active_entities
			trans=Sketchup.active_model.edit_transform
			chain=self.chain
			edges=[]
			(chain.length-1).times {|i|
				p0=chain[i].transform(trans)
				p1=chain[i+1].transform(trans)
				edges.push(ents.add_line([p0,p1]))
			}

		return edges
		end

		def draw_path_group()
			trans=@instance.transformation
			pts=self.chain

			group=Sketchup.active_model.active_entities.add_group
			group_ents=group.entities
			group.transform! trans
			group_ents.add_edges(pts)

			return group
		end

		def load_fence()
			@fence.load_from_defn(@su_defn)
		end

		def valid?
			@su_defn.is_a?(Sketchup::ComponentDefinition) && @su_defn.valid?
		end


		def pmpi()
			@instance.hidden=true
			@instance.set_attribute('PMPI','pmpi_hidden',true)
			path=self.draw_path_group
			path.set_attribute('PMPI','pmpi_path',true)
		end

		def save_fence(skp)
			begin
				fence_name = File.basename(skp,".skp")
				Sketchup.active_model.start_operation("Save Fence",true)
				su_fence_defn = build_prototype(fence_name)
				status = su_fence_defn.save_as(skp)
			rescue
				UI.messagebox("Error saving ForgeStructure.")
				raise
			end
			Sketchup.active_model.abort_operation
		end

		def build_prototype(name = "ForgeStructure")

			max_post_height = 0
			fence_length = 48.0
			num_posts = @fence.count_posts

			if num_posts > 0
				posts = @fence.posts
				max_spacing = posts.map{ |post| post.spacing }.max

				post_defs = posts.map{ |p| p.component_definition }.uniq
				post_heights_max = post_defs.map{ |d| d.bounds.depth }.max
				max_post_height = post_heights_max || max_spacing
				fence_length = [max_spacing * 3, max_post_height].max
			end
			p0 = Geom::Point3d.new(0, 0, 0)
			p1 = Geom::Point3d.new(fence_length, 0, 0)
			chain = VBO::ShapeForge::Chain.new([p0, p1])
			a = VBO::ShapeForge::ForgeStructure.add(Sketchup.active_model.entities)
			a.fence = @fence
			a.set_chain(chain)
			g = a.draw(true)
			i = g.to_component
			de = i.definition
			i.erase!
			de.name = Sketchup.active_model.definitions.unique_name(name)
			de
		end

		def load_fence_from_skp(skp)
			defns = Sketchup.active_model.definitions

			Sketchup.active_model.start_operation("Load ForgeStructure", true)
			fence_defn = defns.load(skp)

			return false unless Classify.assembly?(fence_defn)
			@fence = Fence.new
			@fence.load_from_defn(fence_defn)
			self
		end

		def reverse
			path  =  self.chain
			new_path  =  path.reverse
			self.set_chain(new_path)
			self.draw()
		end

		def simplify_polyline(polyline)
			edges = polyline.each_cons(2).to_a

			edges.reject! { |edge| edge[0].distance(edge[1]) < 0.01 }
			return [] if edges.empty?
			simplified_polyline = edges.each_with_object([]) { |edge, result| result << edge[0] }.push(edges.last[1])
		end

		def refresh_thumbnail
			Sketchup.active_model.start_operation("Build Prototype",true)
			defn = build_prototype()
			path = File.join(Sketchup.temp_dir, "assembly.bmp")
			defn.save_thumbnail(path) ? path : nil
		end
		def to_h
	  @fence.to_h
	end
	def to_s
	  to_h.to_json
	end
	def inspect
	  to_h
	end
	end
end
