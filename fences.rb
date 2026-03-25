module VBO::ShapeForge

  class Fence

    attr_reader :description, :posts, :rails, :spans,:name, :chain
    attr_writer :description

    def initialize
      @posts = []
      @rails = []
      @spans = []
      @chain = nil
      self.name = "New Structure"
      @description = "add description..."
      @dict = "PBFence"
    end #init

    def [](key)
      if key.start_with?('Post')
        index = key[4..-1].to_i
        return @posts[index]
      elsif key.start_with?('Rail')
        index = key[4..-1].to_i
        return @rails[index]
      elsif key.start_with?('Span')
        index = key[4..-1].to_i
        return @spans[index]
      else
        return nil
      end
    end

    def name=(value)

      @name = (value)
      return value

    end

    def filename
      illegal="\\\/:*?\"<>|"
      return @name.delete(illegal)
    end

    def add_post(post=Post.new)
      post.name = "P##{SecureRandom.urlsafe_base64(6).gsub(/[^a-zA-Z0-9]/, '')}" if post.name ==""
      @posts.push(post)
    end

    def add_span(span=Span.new)
      span.name = "S##{SecureRandom.urlsafe_base64(6).gsub(/[^a-zA-Z0-9]/, '')}" if span.name ==""
      span.ui_id = @posts[span.support_post_index].ui_id
      @spans.push(span)
    end

    def set_post(post,index)
      @posts[index]=post
    end

    def post_at(index)
      @posts[index]
    end

    def add_rail(span=Rail.new)
      span.name = "P##{SecureRandom.urlsafe_base64(6).gsub(/[^a-zA-Z0-9]/, '')}" if span.name ==""
      @rails.push(span)
    end

    def set_rail(span,index)
      @rails[index]=span
    end

    def rail_at(index)
      @rails[index]
    end

    def count_posts()
      @posts.length
    end

    def count_rails()
      @rails.length
    end

    def delete_post_at(index)
      @posts.delete_at(index)
    end

    def delete_rail_at(index)
      @rails.delete_at(index)
    end

    #
    def calculate_segments(post)
      angle, spacing = post.junction_angle, post.spacing
      post.cal_junctions = calculate_junction_indices(angle, spacing)
      post.cal_segments = create_segments(post.cal_junctions)
      post.cal_segments
    end

    #returns the indicies of the junction points
    def calculate_junction_indices(angle, spacing)
      path=chain.path
      junctions=[]
      num_pts=path.length
      # calculate the estimate spacing
      t_length = chain.path.each_cons(2).inject(0) {|sum, (a, b)| sum + a.distance(b)}
      num_posts = (t_length / spacing).ceil
      e_spacing = t_length / num_posts.to_f
      # puts "t_length: #{t_length.to_m}"
      # puts "s_spacing: #{spacing.to_m}"
      last_length = 0
      (num_pts-2).times {|i|
        v1=path[i].vector_to(path[i+1])
        v2=path[i+1].vector_to(path[i+2])
        # puts "v angle: #{(v1.angle_between(v2)).radians.abs}"
        # puts "angle: #{angle.radians}"
        # puts "last_length: #{last_length.to_m}"
        # puts "v1.length: #{v1.length.to_m}"
        # puts "sum: #{last_length.to_m + v1.length.to_m}"
        # puts "e_spacing: #{e_spacing.to_m}"

        if (v1.angle_between(v2)).abs > angle.degrees
          junctions.push(i+1)
          last_length = 0 if last_length + v1.length >= e_spacing
        else
          last_length += v1.length
        end
      }

      junctions.push(path.length-1)
      # puts junctions.to_s
      return junctions

    end

    def calculate_junction_indices_hash(angle, spacing)
      path=chain.path
      junctions = [[path[0]]]
      num_pts=path.length
      t_length = chain.path.each_cons(2).inject(0) {|sum, (a, b)| sum + a.distance(b)}
      num_posts = (t_length / spacing).ceil
      e_spacing = t_length / num_posts.to_f

      last_length = 0
      (num_pts-2).times {|i|
        v1=path[i].vector_to(path[i+1])
        v2=path[i+1].vector_to(path[i+2])

        if (v1.angle_between(v2)).abs > angle.degrees
          junctions << [path[i+1]]
          last_length = 0 if last_length + v1.length >= e_spacing
        else
          junctions[-1] << path[i+1]
          last_length += v1.length
        end
      }

      junctions[-1] << path[path.length-1]

      return junctions

    end

    #creates a group && a series of curves (segments)
    def create_segments(junctions)

      path=@chain.path
      pt_index=0
      segments=[]

      junctions.each{|junction_index|
        curve_pts=path[pt_index..junction_index]
        segments.push(Curve.new(curve_pts))
        pt_index=junction_index
      }
      # puts "segments: #{segments.to_s}"
      return segments

    end

    def unique_name(str, var)
			while true
				found = self.instance_variable_get(var).find{|c| c.name == str}
				if found.nil?
					break
				else
					if found.name.include?('#')
						if found.name.split('#')[-1].empty?
							str = "#{str} #1"
						else
							a = found.name.split('#')
							str = (a[0..-2] + [a[-1].to_i + 1]).join("#")
						end
					else
						str = "#{str} #1"
					end
				end
			end
			str
		end
    #
    def calc_posts_layout(pts)

      begin
        @chain=Chain.new
        @chain.set_path(pts)
        @posts.each {|post|
          calc_post_layout(post) if post.valid?
        }
      rescue
        @posts.each {|post|	post.clear_instances if post.valid?}
        @chain=nil
        raise
      end


    end


    def calc_post_layout(post)

      segments = calculate_segments(post)
      # puts "segments: #{segments.to_s}"
      post.clear_instances
      num_segments = segments.length

      # junctions = calculate_junction_indices(post.junction_angle.degrees, post.spacing).map{|i| self.chain[i].to_a}
      # junctions = segments.map{|s| s.points[0].to_a}
      junctions = post.cal_junctions
      # junctions.pop

      segments.each {|curve|
        curve_length=curve.length

        is_first_segment=(curve==segments.first)
        is_last_segment=(curve==segments.last)

        # if post.at_infill?

          if post.horizontal_layout?
            curve_length=curve.flattened_length
          end

          first_infill_post_location=get_first_infill_post_location(post,curve,is_first_segment)

          last_infill_post_location=get_last_infill_post_location(post,curve,is_last_segment)

          next if first_infill_post_location==nil || last_infill_post_location==nil
          next if first_infill_post_location>last_infill_post_location

          #calculate the number of posts && the spacing
          spacing=post.spacing
          infill_distance = last_infill_post_location - first_infill_post_location
          num_gaps = (infill_distance / spacing).ceil
          num_posts = is_first_segment ? num_gaps - 1 : num_gaps
          num_posts += 1 if @chain.closed_path?# || !post.at_start

          gap_distance = post.fixed_spacing? ? spacing : infill_distance / num_gaps.to_f

          unless @chain.closed_path?
            if is_first_segment #&& post.at_start?
              add_post_on_curve(post,curve,post.start_setback)
            end
          else
            if is_first_segment  && num_segments>1 #&& post.at_start?
              add_post_on_curve(post,curve,post.start_setback)
            end
          end

          if post.layout == "From Middle"
            mid_post_location = (last_infill_post_location + first_infill_post_location) / 2.0
            location = mid_post_location - (gap_distance * ((num_gaps / 2.0) - 1))
          else
            location = first_infill_post_location
            location += gap_distance if is_first_segment# && post.at_start?
          end
          post.real_spacing = gap_distance
          #add infill posts if we have enough curve length
          if post.spacing < infill_distance
            num_posts.times{|i|
              add_post_on_curve(post,curve,location)
              location += gap_distance
            }
          end
        # end
        if post.layout=="From Start" || !post.fixed_spacing?
          if !is_last_segment && !junctions.include?(curve.points[-1].to_a)
            unless post.junction_setback.abs < 0.001  #prevents duplicate posts at junctions
              add_post_on_curve(post,curve,last_infill_post_location) unless post.fixed_spacing?
            end
          end
        end

        if post.at_junction != "None"
          add_post_on_curve(post,curve,curve_length - post.junction_setback) if !is_last_segment# && !junctions.include?(curve.points[-1].to_a)
          unless post.junction_setback < 0.001  #prevents duplicate posts
            add_post_on_curve(post,curve,post.junction_setback) if !is_first_segment# && !junctions.include?(curve.points[-1].to_a)
          end
        end
        if post.layout=="From Start" || !post.fixed_spacing?
          if is_last_segment
            unless post.end_setback==0.0 && post.start_setback==0.0 && @chain.closed_path?
              add_post_on_curve(post,curve,last_infill_post_location) unless post.fixed_spacing?
            end
          end
        end

        unless @chain.closed_path?
          if is_last_segment && !(post.at_infill? && !post.fixed_spacing?) #&& post.at_end?
            add_post_on_curve(post,curve,curve_length-post.end_setback)
          end
        else
          if is_last_segment && num_segments>1 #&& post.at_end?
            add_post_on_curve(post,curve,curve_length-post.end_setback)
          end
        end
      }
    end


    def get_first_infill_post_location(post,curve,is_first_segment=false)

      if post.horizontal_layout?
        curve_length=curve.flattened_length
      else
        curve_length=curve.length
      end

      start_setback=is_first_segment ? post.start_setback : post.junction_setback

      if curve_length<start_setback
        location=nil
      else
        location=start_setback
      end

      return location

    end


    def get_last_infill_post_location(post, curve, is_last_segment=false)
      if post.horizontal_layout?
        curve_length = curve.flattened_length
      else
        curve_length = curve.length
      end
      end_setback = is_last_segment ? post.end_setback : post.junction_setback

      location = (curve_length > end_setback) ? (curve_length - end_setback) : nil

      return location
    end



    def add_post_on_curve(post,curve,distance_from_curve_start)

      trans_edge = get_post_location_on_curve(post,curve,distance_from_curve_start)
      post_transformation = trans_edge[0]
      edge = trans_edge[1]
      post_location = post_transformation.origin

      x_axis = post_transformation.xaxis
      y_axis = post_transformation.yaxis
      z_axis = post_transformation.zaxis

      #offset the post location according to the input offsets
      x_offset = x_axis.clone
      x_offset.length = post.x_offset

      y_offset=y_axis.clone
      y_offset.length= post.y_offset

      global_z_offset = Z_AXIS.clone
      global_z_offset.length = post.y_offset

      if post.use_global_up_offset
        total_offset = x_offset + global_z_offset
      else
        total_offset = x_offset + y_offset
      end
      post_location = post_location.offset(total_offset)

      if post.stay_vertical?
        if x_axis.parallel?(Z_AXIS)
          trans = Geom::Transformation.new(z_axis.reverse,z_axis.cross(x_axis),Z_AXIS,post_location)
        else
          trans = Geom::Transformation.new(Z_AXIS.cross(x_axis),x_axis.reverse,Z_AXIS,post_location)
        end
      else
        trans = Geom::Transformation.new(z_axis.reverse,x_axis.reverse,y_axis,post_location)
      end



      case post.rotation
        when "0","90","180","270"
          angle=post.rotation.to_f.degrees
          rot_trans=Geom::Transformation.rotation(Geom::Point3d.new(0,0,0),trans.zaxis,angle)
        when "Average"
          angle=get_average_post_angle(trans,curve,distance_from_curve_start)
          rot_trans=Geom::Transformation.rotation(Geom::Point3d.new(0,0,0),trans.zaxis,angle)
        when "Random"
          angle=rand*Math::PI*2.0
          rot_trans=Geom::Transformation.rotation(Geom::Point3d.new(0,0,0),trans.zaxis,angle)
        when "Smooth"
          rot_trans=Geom::Transformation.new
        else
          angle=post.rotation.to_f.degrees
          rot_trans=Geom::Transformation.rotation(Geom::Point3d.new(0,0,0),trans.zaxis,angle)
      end

      if post.mirror?
        scale_trans=Geom::Transformation.scaling(1.0,-1.0,1.0)
      else
        scale_trans=Geom::Transformation.new
      end

      trans=trans*rot_trans*scale_trans

      post.add_instance(trans,edge)


    end


    def get_post_location_on_curve(post,curve,distance_from_curve_start)

      curve_pts=curve.points

      x=0.0
      pt_index=0

      edge_start_point=curve_pts[0]
      edge_end_point=curve_pts[1]

      xy_plane=[Geom::Point3d.new(0,0,0), Geom::Vector3d.new(0,0,1)]
      is_horizontal_layout=post.horizontal_layout?
      is_horizontal_layout=false unless post.at_infill?

      if is_horizontal_layout
        current_edge_length=edge_start_point.project_to_plane(xy_plane).distance(edge_end_point.project_to_plane(xy_plane))
      else
        current_edge_length=edge_start_point.distance(edge_end_point)
      end

      if distance_from_curve_start<=0.0
        distance_along_this_edge=distance_from_curve_start
        edge_line_containing_post=[edge_start_point,edge_end_point]
      elsif distance_from_curve_start>curve.length
        edge_start_point=curve_pts[-2]
        edge_end_point=curve_pts[-1]
        distance_along_this_edge=edge_start_point.distance(edge_end_point)+(distance_from_curve_start-curve.length.to_f)
        edge_line_containing_post=[edge_start_point,edge_end_point]
      else
        while (x<distance_from_curve_start)

          edge_start_point=curve_pts[pt_index]
          edge_end_point=curve_pts[pt_index+1]

          if is_horizontal_layout && post.at_infill?
            edge_start_point=edge_start_point.project_to_plane(xy_plane)
            edge_end_point=edge_end_point.project_to_plane(xy_plane)
          end

          current_edge_length=edge_start_point.distance(edge_end_point)
          x=x+current_edge_length
          pt_index+=1
        end
        distance_along_this_edge=distance_from_curve_start-(x-current_edge_length)
        edge_line_containing_post=[curve_pts[pt_index-1],curve_pts[pt_index]]
      end

      overall_path_pt_index=@chain.path.index(edge_line_containing_post[0])
      curve_axis_transform=@chain.transformation_at(overall_path_pt_index)
      x_axis=curve_axis_transform.xaxis
      y_axis=curve_axis_transform.yaxis
      z_axis=curve_axis_transform.zaxis

      offset_along_edge=z_axis.reverse
      if is_horizontal_layout && !(z_axis.parallel?(Z_AXIS))
        offset_along_edge.z=0.0
      end
      offset_along_edge.length=distance_along_this_edge

      if is_horizontal_layout
        flattened_edge_line_containing_post=[edge_start_point,edge_end_point]
        flattened_post_location=edge_start_point.offset(offset_along_edge)
        vertical_line=[flattened_post_location,Geom::Vector3d.new(0,0,1)]
        post_location=Geom.intersect_line_line(vertical_line, edge_line_containing_post)
        if post_location==nil
          post_location=edge_start_point.offset(offset_along_edge)
        end
      else
        post_location=edge_start_point.offset(offset_along_edge)
      end

      if post.rotation=="Smooth"
        num_points=@chain.num_points
        edges=@chain.edges()
        num_edges=edges.length

        if (overall_path_pt_index!=(num_points-1)) && (num_points>2)

          prev_trans=@chain.transformation_at(overall_path_pt_index-1)
          prev_edge=edges[overall_path_pt_index-1]
          prev_edge_length=prev_edge[0].vector_to(prev_edge[1]).length

          if @chain.closed_path? && overall_path_pt_index==(num_points-2)
            next_trans=@chain.transformation_at(0)
            next_edge=edges[0]
            next_edge_length=next_edge[0].vector_to(next_edge[1]).length
          else
            if overall_path_pt_index==(num_points-2)
              next_trans=@chain.transformation_at(overall_path_pt_index)
              next_edge=edges[overall_path_pt_index]
              next_edge_length=next_edge[0].vector_to(next_edge[1]).length
            else
              next_trans=@chain.transformation_at(overall_path_pt_index+1)
              next_edge=edges[overall_path_pt_index+1]
              next_edge_length=next_edge[0].vector_to(next_edge[1]).length
            end
          end

          half_prev_edge_length=prev_edge_length/2.0
          half_next_edge_length=next_edge_length/2.0
          half_current_edge_length=current_edge_length/2.0

          dist_midprev_midthis=half_prev_edge_length+half_current_edge_length
          dist_midthis_midnext=half_current_edge_length+half_next_edge_length

          ratio_along_this_edge=distance_along_this_edge/current_edge_length
          if (ratio_along_this_edge)<=0.5
            factor=(half_prev_edge_length+distance_along_this_edge)/dist_midprev_midthis
            curve_axis_transform=Geom::Transformation.interpolate(prev_trans,curve_axis_transform,factor)
          else
            dist_from_this_edge_end=(1.0-ratio_along_this_edge)*current_edge_length
            factor=(half_current_edge_length-dist_from_this_edge_end)/dist_midthis_midnext
            curve_axis_transform=Geom::Transformation.interpolate(curve_axis_transform,next_trans,factor)
          end
          x_axis=curve_axis_transform.xaxis
          y_axis=curve_axis_transform.yaxis
          z_axis=curve_axis_transform.zaxis

        end
      end

      trans=Geom::Transformation.new(x_axis,y_axis,z_axis,post_location)

      return trans,edge_line_containing_post

    end

    #
    def get_average_post_angle(post_trans,curve,distance_from_curve_start)

      all_points=@chain.path
      all_edges=[]

      up_axis=post_trans.zaxis
      temp_chain=Chain.new(all_points)
      all_edges=temp_chain.edges()

      if distance_from_curve_start==0.0
        next_edge=curve.first_edge
        next_edge_index=all_edges.index(next_edge)
        if next_edge_index==0
          angle=0.0
        else
          previous_edge=all_edges[next_edge_index-1]
          v1=previous_edge[0].vector_to(previous_edge[1])
          v2=next_edge[0].vector_to(next_edge[1])
          v3=v1.cross(v2)
          angle=((v1.angle_between(v2))/2.0)
          if v3.angle_between(up_axis)<(Math::PI/2.0)
            angle=-angle
          end
        end
      elsif distance_from_curve_start==curve.length.to_f
        previous_edge=curve.last_edge
        previous_edge_index=all_edges.index(previous_edge)
        if previous_edge_index==(all_edges.length-1)
          angle=0.0
        else
          next_edge=all_edges[previous_edge_index+1]
          v1=previous_edge[0].vector_to(previous_edge[1])
          v2=next_edge[0].vector_to(next_edge[1])
          v3=v1.cross(v2)
          angle=(v1.angle_between(v2))/2.0
          if v3.angle_between(up_axis)<(Math::PI/2.0)
            angle=-angle
          end
        end
      else
        angle=0.0
      end
      return angle
    end


    def load_from_defn(su_defn)

      new_posts = []
      new_rails = []
      new_spans = []
      dicts = su_defn.attribute_dictionaries

      if dicts && dicts[@dict]

        fence_dict = dicts[@dict]
        self.description = su_defn.description
        self.name = su_defn.get_attribute(@dict,"name",su_defn.name)
        fence_dict.each_pair {|key,value|

        if key.split("Post").length > 1
          post_index = key.split("Post")[1].to_i
          new_post = Post.new(value)
          new_posts[post_index] = new_post
        elsif key.split("Rail").length > 1
          rail_index = key.split("Rail")[1].to_i
          new_rail = Rail.new(value)
          new_rails[rail_index] = new_rail
        elsif key.split("Span").length > 1
          span_index = key.split("Span")[1].to_i
          new_span = Span.new(value)
          new_spans[span_index] = new_span
        end
        }

        new_posts.each {|post| self.add_post(post)}
        new_rails.each {|span| self.add_rail(span)}
        new_spans.each {|span| self.add_span(span)}

      end

    end

    def load_from_object(str)
      str.keys.each{|v|
        instance_variable_set(VBO::ShapeForge.camel_to_snake(v), str[v])
      }
      @posts.map!{|c| Post.new(c)}
      @rails.map!{|c| Rail.new(c)}
      @spans.map!{|c| Span.new(c)}
      @spans.each{|sp|
        sp.ui_id = @posts[sp.support_post_index].ui_id
      }
    end

    def post_spans(post)
      if post.is_a?(String)
        @spans.find_all{|sp|
          index == post.split("Post")[1].to_i
          sp.ui_id == @posts[index].ui_id
        }
      elsif post.is_a?(Integer)
        @spans.find_all{|sp|
          # sp.support_post_index == post
          sp.ui_id == @posts[post].ui_id
        }
      elsif post.is_a?(Post)
        @spans.find_all{|sp|
          # found_post =  @posts[sp.support_post_index]
          # found_post == post && found_post.name == post.name
          sp.ui_id == post.ui_id
        }
      end
    end

    def load_from_string(string)
      # UI.messagebox string
      str = JSON.parse(string)
      load_from_object(str)
    end

    def to_h
      instance_variables.map{|c|
        [
          VBO::ShapeForge.snake_to_camel(c),
          VBO::ShapeForge.save_out([instance_variable_get(c)])[0]
        ]
      }.to_h
    end
    def to_s
      to_h.to_json
    end
    def inspect
      to_h
    end

  end

end
