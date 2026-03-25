module VBO::ShapeForge
	module DRAWVIEW
		module_function
		def fill_polygon(view, pts, color, alpha = 100)
			polygon = Geom.tesselate pts
			color.alpha = alpha
			view.drawing_color = color
			view.draw2d(GL_TRIANGLES, polygon)
		end
		def self.draw_edges_ref(path,color, view)
			if path.to_a[-1] && path.to_a[-2]
				edges =  path.to_a[-2].definition.entities.find_all{|c| c.is_a?(Sketchup::Edge) && !c.soft? && !c.hidden? && !c.smooth?}
				tr = Sketchup::InstancePath.new(path).transformation
				edges.each{|edge|
					points3d = edge.vertices.map{|c| c.position.transform(tr)}
					points2d = points3d.map{|c| view.screen_coords(c)}

					view.line_width=2
					view.line_stipple = ""
					color.alpha = 50
					view.drawing_color = color
					view.draw2d(GL_LINES,points2d)
					view.line_width=5
					view.line_stipple = ""
					color.alpha = 200
					view.drawing_color = color
					#view.draw(GL_LINES,points3d)
				}
			end
		end
		def self.draw_face_ref(path,color, view)
			if path.to_a[-1].is_a? Sketchup::Face
				face =  path.to_a[-1]
				tr = Sketchup::InstancePath.new(path).transformation
				face.loops.each{|lo|
					points3d = lo.vertices.map{|c| c.position.transform(tr)}
					points2d = points3d.map{|c| view.screen_coords(c)}

					view.line_width=3
					view.line_stipple = ""
					color.alpha = 50
					view.drawing_color = color
					view.draw2d(GL_LINE_LOOP,points2d)
					view.line_width=5
					view.line_stipple = ""
					color.alpha = 255
					view.drawing_color = color
					view.draw(GL_LINE_LOOP,points3d)
				}
				color.alpha = 30
				view.drawing_color = color
				mesh = face.mesh(0)
				ps   = (1..mesh.count_polygons).map { |i|
				mesh.polygon_points_at(i).map{ |p|
					view.screen_coords(p.transform(tr))
				}
				}.flatten
				view.draw2d(GL_TRIANGLES, ps)
			end
		end
		def draw_textbox(view, point, text, align = TextAlignLeft, color = Sketchup::Color.new('white'), background = Sketchup::Color.new('gray'), font_size = 10)

			if background
				bounds = view.text_bounds(point, text, {
					font: "Arial",
					size: font_size * UI.scale_factor,
					bold: true,
					color: color,
					align: align,
					vertical_align: align == TextAlignCenter ? TextVerticalAlignCenter : TextVerticalAlignBoundsTop
				})

				x1, y1 = bounds.upper_left.to_a
				x2, y2 = bounds.lower_right.to_a
				points = [
					Geom::Point3d.new(x1, y1),
					Geom::Point3d.new(x1, y2),
					Geom::Point3d.new(x2, y2),
					Geom::Point3d.new(x2, y1),
				]

				view.drawing_color = background
				view.draw2d(GL_QUADS, points)
			end

			view.draw_text(point, text, {
				font: "Arial",
				size: font_size * UI.scale_factor,
				bold: true,color:
				color,
				align: align,
				vertical_align: align == TextAlignCenter ? TextVerticalAlignCenter : TextVerticalAlignBoundsTop
			})
		end

		def display_name(mat)
			if mat.nil?
				return 'Default'
				#Sketchup.active_model.materials.unique_name('Default')
			elsif mat.is_a?(String)
				return mat
			else
				case mat.typename
				when 'Material'
					if ["<",">"].any?{|c| mat.name.include?(c)}
						return Sketchup.active_model.materials.unique_name(mat.name.gsub("<","&lt"))#.gsub(">","]"))
					else
						return mat.name
					end
				when 'Layer'
					if ["<",">"].any?{|c| mat.name.include?(c)}
						return Sketchup.active_model.layers.unique_name(mat.name.gsub("<","&lt"))#.gsub(">","]"))
					else
						return Sketchup.version.to_i.ceil >= 20 ? mat.name.gsub("Layer0", "Untagged") :  mat.name
					end
				when 'ComponentDefinition'
					if ["<",">"].any?{|c| mat.name.include?(c)}
						return Sketchup.active_model.definitions.unique_name(mat.name.gsub("<","&lt"))#.gsub(">","]"))
					else
						return mat.name
					end
				end
			end
		end
		def draw_face(path, color, view, center = false, alpha = 60)
			if path.to_a[-1].is_a? Sketchup::Face
				face =  path.to_a[-1]
				tr = Sketchup::InstancePath.new(path).transformation
				face.loops.each{|lo|
					points3d = lo.vertices.map{|c| c.position.transform(tr)}
					points2d = points3d.map{|c| view.screen_coords(c)}

					view.line_width=3
					view.line_stipple = ""
					color.alpha = 100
					view.drawing_color = color
					view.draw2d(GL_LINE_LOOP,points2d)
					view.line_width=5
					view.line_stipple = ""
					color.alpha = 255
					view.drawing_color = color
					view.draw(GL_LINE_LOOP,points3d)
				}
				color.alpha = alpha
				view.drawing_color = color
				if alpha < 200
					mesh = face.mesh(0)
					ps   = (1..mesh.count_polygons).map { |i|
						mesh.polygon_points_at(i).map{ |p|
							view.screen_coords(p.transform(tr))
						}
					}.flatten
					view.draw2d(GL_TRIANGLES, ps)
				else
					mesh = face.mesh(0)
					ps   = (1..mesh.count_polygons).map { |i|
						mesh.polygon_points_at(i).map{ |p|
							p.transform(tr)
						}
					}.flatten
					view.draw(GL_TRIANGLES, ps)
				end
				if center
					view.line_width = 1
					view.draw_points(face.bounds.center.transform(tr),15 * UI.scale_factor,5, color)
				end
			end
		end
		def draw_face3d(path, color, view)
			if path.to_a[-1].is_a? Sketchup::Face
				face =  path.to_a[-1]
				tr = Sketchup::InstancePath.new(path).transformation
				color.alpha = 60
				view.drawing_color = color
				mesh = face.mesh(0)
				ps   = (1..mesh.count_polygons).map { |i|
					mesh.polygon_points_at(i).map{ |p|
						p.transform(tr)
					}
				}.flatten
				view.draw(GL_TRIANGLES, ps)
				face.loops.each{|lo|
					points3d = lo.vertices.map{|c| c.position.transform(tr)}
					view.line_width = 2
					view.line_stipple = ""
					color.alpha = 255
					view.drawing_color = Sketchup::Color.new('Black')
					view.draw(GL_LINE_LOOP,points3d)
				}
			end
		end
		def draw_arrow2d(view, pp1, pp2, paintcolor=nil)
			# puts "draw_arrow2d #{pp1} to #{pp2}"
			p1, p2 = [pp1,pp2].map{|c| view.screen_coords(c)}
			return unless p1.z > 1.0 && p2.z > 1.0
			vec = p1.vector_to(p2)
			return unless vec.valid?
				# Draw an arrow at the end of the vector.
				vec.length = 7 * UI.scale_factor# pixels
				side = vec * Z_AXIS
				tip = [p2, p2-vec+side-vec, p2-vec-side-vec]
				view.drawing_color = paintcolor if paintcolor
				view.line_stipple = "-"
				view.draw2d(GL_LINE_STRIP, p1,p2)
				view.draw2d(GL_POLYGON, tip)
				view.line_stipple = "-"
				view.draw2d(GL_LINE_LOOP, tip)
		end
		def draw_boundingbox_ref(view, bounds, color, t, fill = true)
			# Check if bounds center is too close to camera (causes flip)
			center = bounds.center.transform(t)
			screen_center = view.screen_coords(center)
			if screen_center.z <= 5.0
				return
			end
			view.line_width=3
			view.line_stipple = ""
			color.alpha = 100
			view.drawing_color = color
			# Detect 2d bounding box, it needs only one face instead of 6 overlapping faces.
			if bounds.width == 0 || bounds.height == 0 || bounds.depth == 0
				if bounds.width == 0
					ps  = [0, 2, 6, 4].map { |i| bounds.corner(i).transform(t) }
				elsif bounds.height == 0
					ps  = [0, 1, 5, 4].map { |i| bounds.corner(i).transform(t) }
				elsif bounds.depth == 0
					ps  = [0, 1, 3, 2].map { |i| bounds.corner(i).transform(t) }
				end
				# Draw lines
				view.draw2d(GL_LINE_LOOP, ps.map { |p| view.screen_coords(p) })
				# Draw polygons
					color.alpha = 100
					view.drawing_color = color
					view.draw(GL_QUADS, ps)
			else
				ps  = (0..7).map { |i| bounds.corner(i).transform(t) }
				# A quad strip around the bounding box
				ps1 = [ps[0], ps[1], ps[2], ps[3], ps[6], ps[7], ps[4], ps[5], ps[0], ps[1]]
				# Two quads not covered by the quad strip
				ps2 = [ps[0], ps[2], ps[6], ps[4], ps[1], ps[3], ps[7], ps[5]]
				# Quad strips ps1, ps2 can be interpreted as lines, but these are missing:
				ps3 = [ps[0], ps[4], ps[1], ps[5], ps[2], ps[6], ps[3], ps[7]]
				# Draw lines
				color.alpha = 100
				view.drawing_color = color
				view.draw2d(GL_LINES, [ps1, ps2, ps3].flatten.map { |p| view.screen_coords(p) })
				# Draw polygons
				if fill
					color.alpha = 60
					view.drawing_color = color
					view.draw(GL_QUAD_STRIP, ps1)
					view.draw(GL_QUADS, ps2)
				end
			end
		end

		def draw_point_2d(view, point, radius, color)
			p1 = point.offset([radius,0,0])
			p2 = point.offset([-radius,0,0])
			p3 = point.offset([0, -radius,0])
			p4 = point.offset([0, radius,0])
			color = Sketchup::Color.new(color)
			color.alpha = 255
			view.drawing_color = color
			view.line_width = 2
			view.line_stipple= ""
			view.draw2d(GL_LINE_STRIP, p1, p2)
			view.draw2d(GL_LINE_STRIP, p3, p4)
		end

		def draw_instance_ref(path,color, view, fill = true)
			return if path.nil?
			if path.to_a[-1].is_a?(Sketchup::Group) || path.to_a[-1].is_a?(Sketchup::ComponentInstance)
				gc =  path.to_a[-1]
				tr = Sketchup::InstancePath.new(path[0..path.length-1]).transformation
				if gc.is_a?(Sketchup::Group)
					bbs =  gc.local_bounds
				else
					bbs =  gc.definition.bounds
				end
				draw_boundingbox_ref(view, bbs, color, tr, fill)
			end
		end

		def draw_path3d(view, chain, paintcolor = nil)
			if chain.length > 1
				# Check if any point is too close to camera (causes flip)
				min_z = chain.map{|p| view.screen_coords(p).z}.min
				if min_z <= 5.0
					return
				end 
				if paintcolor.nil?
					view.set_color_from_line(chain[-2], chain[-1])
					view.draw_points([chain[0]], 10 * UI.scale_factor, 4, Sketchup::Color.new('gray'))
				else
					paintcolor.alpha = 255
					view.drawing_color = paintcolor
					view.draw_points([chain[0]], 15 * UI.scale_factor, 4, paintcolor)
					view.draw_points(chain[1..chain.length - 2], 8 * UI.scale_factor,  2, paintcolor) if chain.length > 2
				end
				view.line_width = 2.5
				view.line_stipple = ""
				view.drawing_color = Sketchup.active_model.rendering_options["BackgroundColor"]
				view.draw(GL_LINE_STRIP, chain)
				draw_arrow2d(view,chain[-2], chain[-1])

				view.line_width = 2
				view.line_stipple = "-"
				if paintcolor
					paintcolor.alpha = 150
					view.drawing_color = paintcolor
				else
					view.set_color_from_line(chain[-2], chain[-1])

				end
				view.draw(GL_LINE_STRIP, chain)

				if paintcolor
					paintcolor.alpha = 255
					view.drawing_color = paintcolor
				else
					view.set_color_from_line(chain[-2], chain[-1])
				end
				view.line_width = 2
				view.line_stipple = ""
				view.draw(GL_LINE_STRIP, chain)
				draw_arrow2d(view,chain[-2], chain[-1])
			end
		end
	end

end
