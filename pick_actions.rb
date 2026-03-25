class VBO::ShapeForge::ForgeStructureController

  def pick_x_offset(value)
    model = Sketchup.active_model
    sel = model.selection
    return if sel.length != 1 || !VBO::ShapeForge::Classify.assembly?(sel[0])

    model.tools.pop_tool if model.tools.active_tool.to_s.include?('Pick') || model.tools.active_tool.is_a?(VBO::ShapeForge::SelHilight)

    if value.start_with?('Post')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      a_vec = ass_chain[0].vector_to(ass_chain[1])
      x_vec = (a_vec * Z_AXIS)
      pre_length = ass.fence.posts[value.split('Post')[1].to_i].x_offset
      po = ass_chain[0].offset(x_vec, pre_length)
      t = VBO::ShapeForge::PickDistanceGetter.new(x_vec, ass_chain, po, pre_length)
      t.prefix = "Post X Offset"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(x_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.posts[value.split('Post')[1].to_i].x_offset += distance
        self.refresh(@assembly)
        model.start_operation("Change Post X Offset", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    elsif value.start_with?('Rail')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      rail = ass.fence.rails[value.split('Rail')[1].to_i]
      oxy_plane = [ORIGIN, Z_AXIS]

      a_vec = ass_chain[0].vector_to(ass_chain[1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS
      pre_length = rail.x_offset
      po = ass_chain[0].offset(x_vec, pre_length)

      t = VBO::ShapeForge::PickDistanceGetter.new(x_vec, ass_chain, po, pre_length)
      t.prefix = "Rail X Offset"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(x_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.rails[value.split('Rail')[1].to_i].x_offset += distance
        self.refresh(@assembly)
        model.start_operation("Change Rail X Offset", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    elsif value.start_with?('Span')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}

      span = ass.fence.spans[value.split('Span')[1].to_i]
      pre_length = span.x_offset
      # sp_post = ass.fence.posts[span.support_post_index]
      sp_post = ass.fence.posts.find{|po| po.ui_id == span.ui_id}
      # calculate the nearest post
      sp_post_instances = sp_post.instances.values.flatten.map{|v| v.origin}.uniq{|v| v.to_a}

      sp_post_instances_and_junctions = sp_post.instances.map{|edge, trans|
        eds = sp_post.offset_chain(VBO::ShapeForge::Chain.new(edge), sp_post.use_global_up_offset).to_a
        [eds[0] ] + trans.map{|c| c.origin} + [eds[1]]
      }.flatten.uniq{|c| c.to_a.map{|d| d.round(3)}}

      nearest_post_coords = sp_post_instances.min_by{|c| c.distance(Sketchup.active_model.active_view.camera.eye)}

      index = sp_post_instances_and_junctions.index(nearest_post_coords)
      if index == sp_post_instances_and_junctions.length - 1
        index = sp_post_instances_and_junctions.length - 2
      end
      a_vec = sp_post_instances_and_junctions[index].vector_to(sp_post_instances_and_junctions[index + 1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      po = nearest_post_coords
      po.offset!(x_vec, span.x_offset) if span.x_offset.abs > 0.001
      po.offset!(y_vec, span.y_offset) if span.y_offset.abs > 0.001
      po.offset!(a_vec, span.start_setback) if span.start_setback.abs > 0.001

      t = VBO::ShapeForge::PickDistanceGetter.new(x_vec, ass_chain, po, pre_length)
      t.prefix = "Span X Offset"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(x_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.spans[value.split('Span')[1].to_i].x_offset += distance
        self.refresh(@assembly)
        model.start_operation("Change Span X Offset", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    end
  end

  def pick_y_offset(value)
    # puts "pick y offset"
    model = Sketchup.active_model
    sel = model.selection
    return if sel.length != 1 || !VBO::ShapeForge::Classify.assembly?(sel[0])

    model.tools.pop_tool if model.tools.active_tool.to_s.include?('Pick')

    if value.start_with?('Post')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      a_vec = ass_chain[0].vector_to(ass_chain[1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      pre_length = ass.fence.posts[value.split('Post')[1].to_i].y_offset
      po = ass_chain[0].offset(y_vec, pre_length)
      t = VBO::ShapeForge::PickDistanceGetter.new(y_vec, ass_chain, po, pre_length)
      t.prefix = "Post Y Offset"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(y_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.posts[value.split('Post')[1].to_i].y_offset += distance
        self.refresh(@assembly)
        model.start_operation("Change Post Y Offset", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    elsif value.start_with?('Rail')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      a_vec = ass_chain[0].vector_to(ass_chain[1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      pre_length = ass.fence.rails[value.split('Rail')[1].to_i].y_offset
      po = ass_chain[0].offset(y_vec, pre_length)
      t = VBO::ShapeForge::PickDistanceGetter.new(y_vec, ass_chain, po, pre_length)
      t.prefix = "Rail Y Offset"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(y_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.rails[value.split('Rail')[1].to_i].y_offset += distance
        self.refresh(@assembly)
        model.start_operation("Change Rail Y Offset", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    elsif value.start_with?('Span')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}

      span = ass.fence.spans[value.split('Span')[1].to_i]
      pre_length = span.y_offset

      sp_post = ass.fence.posts[span.support_post_index]
      # calculate the nearest post

      sp_post_instances = sp_post.instances.map{|edge, trans|
        eds = sp_post.offset_chain(VBO::ShapeForge::Chain.new(edge), sp_post.use_global_up_offset).to_a
        [eds[0] ] + trans.map{|c| c.origin} + [eds[1]]
      }.flatten.uniq{|c| c.to_a}
      nearest_post_coords = sp_post_instances.min_by{|c| c.distance(Sketchup.active_model.active_view.camera.eye)}

      index = sp_post_instances.index(nearest_post_coords)

      if index == sp_post_instances.length - 1
        index = sp_post_instances.length - 2
      end

      a_vec = sp_post_instances[index].vector_to(sp_post_instances[index + 1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS


      po = nearest_post_coords#.offset(a_vec, span.start_setback)
      po.offset!(y_vec, pre_length)

      t = VBO::ShapeForge::PickDistanceGetter.new(y_vec, ass_chain, po, pre_length)
      t.prefix = "Span Y Offset"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(y_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.spans[value.split('Span')[1].to_i].y_offset += distance
        self.refresh(@assembly)
        model.start_operation("Change Span Y Offset", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    end
  end

  def pick_start_setback(value)

    model = Sketchup.active_model
    sel = model.selection
    return if sel.length != 1 || !VBO::ShapeForge::Classify.assembly?(sel[0])

    model.tools.pop_tool if model.tools.active_tool.to_s.include?('Pick')

    if value.start_with?('Post')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}

      a_vec = ass_chain[0].vector_to(ass_chain[1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      pre_length = ass.fence.posts[value.split('Post')[1].to_i].start_setback
      po = ass_chain[0].offset(a_vec, pre_length)
      t = VBO::ShapeForge::PickDistanceGetter.new(a_vec, ass_chain, po, pre_length)
      t.prefix = "Post Start Setback"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(a_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.posts[value.split('Post')[1].to_i].start_setback += distance
        self.refresh(@assembly)
        model.start_operation("Change Post Start Setback", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    elsif value.start_with?('Rail')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      rail = ass.fence.rails[value.split('Rail')[1].to_i]
      oxy_plane = [ORIGIN, Z_AXIS]

      a_vec = ass_chain[0].vector_to(ass_chain[1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      pre_length = ass.fence.rails[value.split('Rail')[1].to_i].start_setback
      po = ass_chain[0].offset(a_vec, pre_length)
      t = VBO::ShapeForge::PickDistanceGetter.new(a_vec, ass_chain, po, pre_length)
      t.prefix = "Rail Start Setback"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        if p1.distance(p2) > 0.001
          vec = p1.vector_to(p2)

          distance = vec.samedirection?(a_vec) ? p1.distance(p2) : - p1.distance(p2)
          @assembly.fence.rails[value.split('Rail')[1].to_i].start_setback += distance
          self.refresh(@assembly)
          model.start_operation("Change Rail Start Setback", true)
          self.apply
          model.commit_operation
          model.tools.pop_tool
          refresh(@assembly, value)
        end
      }
      model.tools.push_tool t
    elsif value.start_with?('Span')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      span = ass.fence.spans[value.split('Span')[1].to_i]
      pre_length = span.start_setback

      sp_post = ass.fence.posts[span.support_post_index]

      # calculate the nearest post
      sp_post_instances = sp_post.instances.values.flatten.map{|v| v.origin}.uniq{|v| v.to_a}

      sp_post_instances_and_junctions = sp_post.instances.map{|edge, trans|
        eds = sp_post.offset_chain(VBO::ShapeForge::Chain.new(edge), sp_post.use_global_up_offset).to_a
        [eds[0] ] + trans.map{|c| c.origin} + [eds[1]]
      }.flatten.uniq{|c| c.to_a}

      nearest_post_coords = sp_post_instances.min_by{|c| c.distance(Sketchup.active_model.active_view.camera.eye)}

      index = sp_post_instances_and_junctions.index(nearest_post_coords)

      if index == sp_post_instances_and_junctions.length - 1
        index = sp_post_instances_and_junctions.length - 2
        nearest_post_coords = sp_post_instances_and_junctions[-2]
      end

      a_vec = sp_post_instances_and_junctions[index].vector_to(sp_post_instances_and_junctions[index + 1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      po = nearest_post_coords
      po.offset!(x_vec, span.x_offset) if span.x_offset.abs > 0.001
      po.offset!(y_vec, span.y_offset) if span.y_offset.abs > 0.001
      po.offset!(a_vec, pre_length) if pre_length.abs > 0.001


      t = VBO::ShapeForge::PickDistanceGetter.new(a_vec, ass_chain, po, pre_length)
      t.prefix = "Span Start Setback"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(a_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.spans[value.split('Span')[1].to_i].start_setback += distance
        self.refresh(@assembly)
        model.start_operation("Change Span Start Setback", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    end
  end

  def pick_junction_setback(value)

    model = Sketchup.active_model
    sel = model.selection
    return if sel.length != 1 || !VBO::ShapeForge::Classify.assembly?(sel[0])

    model.tools.pop_tool if model.tools.active_tool.to_s.include?('Pick')

    if value.start_with?('Post')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      return if ass_chain.length <=2
      a_vec = ass_chain[1].vector_to(ass_chain[2])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      pre_length = ass.fence.posts[value.split('Post')[1].to_i].junction_setback
      po = ass_chain[1].offset(a_vec, pre_length)
      t = VBO::ShapeForge::PickDistanceGetter.new(a_vec, ass_chain, po, pre_length)
      t.prefix = "Post Junction Setback"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(a_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.posts[value.split('Post')[1].to_i].junction_setback += distance
        self.refresh(@assembly)
        model.start_operation("Change Post Junction Setback", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    end
  end

  def pick_end_setback(value)

    model = Sketchup.active_model
    sel = model.selection
    return if sel.length != 1 || !VBO::ShapeForge::Classify.assembly?(sel[0])

    model.tools.pop_tool if model.tools.active_tool.to_s.include?('Pick')

    if value.start_with?('Post')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      a_vec = ass_chain[-1].vector_to(ass_chain[-2])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      pre_length = ass.fence.posts[value.split('Post')[1].to_i].end_setback
      po = ass_chain[-1].offset(a_vec, pre_length)
      t = VBO::ShapeForge::PickDistanceGetter.new(a_vec, ass_chain, po, pre_length)
      t.prefix = "Post End Setback"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(a_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.posts[value.split('Post')[1].to_i].end_setback += distance
        self.refresh(@assembly)
        model.start_operation("Change Post End Setback", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    elsif value.start_with?('Rail')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}
      a_vec = ass_chain[-1].vector_to(ass_chain[-2])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS

      pre_length = ass.fence.rails[value.split('Rail')[1].to_i].end_setback
      po = ass_chain[-1].offset(a_vec, pre_length)
      t = VBO::ShapeForge::PickDistanceGetter.new(a_vec, ass_chain, po, pre_length)
      t.prefix = "Rail End Setback"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(a_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.rails[value.split('Rail')[1].to_i].end_setback += distance
        self.refresh(@assembly)
        model.start_operation("Change Rail End Setback", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    elsif value.start_with?('Span')
      ass = VBO::ShapeForge::ForgeStructure.get(sel[0])
      ass_chain = ass.chain.map{|c| c.transform(sel[0].transformation)}

      span = ass.fence.spans[value.split('Span')[1].to_i]
      pre_length = span.end_setback

      sp_post = ass.fence.posts[span.support_post_index]

      # calculate the nearest post
      sp_post_instances = sp_post.instances.values.flatten.map{|v| v.origin}.uniq{|v| v.to_a}

      sp_post_instances_and_junctions = sp_post.instances.map{|edge, trans|
        eds = sp_post.offset_chain(VBO::ShapeForge::Chain.new(edge), sp_post.use_global_up_offset).to_a
        [eds[0] ] + trans.map{|c| c.origin} + [eds[1]]
      }.flatten.uniq{|c| c.to_a}

      nearest_post_coords = sp_post_instances.min_by{|c| c.distance(Sketchup.active_model.active_view.camera.eye)}

      index = sp_post_instances_and_junctions.index(nearest_post_coords)
      if index == 0
        index = 1
        nearest_post_coords = sp_post_instances_and_junctions[1]
      end
      a_vec = sp_post_instances_and_junctions[index].vector_to(sp_post_instances_and_junctions[index - 1])
      x_vec = (a_vec * Z_AXIS)
      y_vec = Z_AXIS


      po = nearest_post_coords
      po.offset!(x_vec, span.x_offset) if span.x_offset.abs > 0.001
      po.offset!(y_vec, span.y_offset) if span.y_offset.abs > 0.001
      po.offset!(a_vec, pre_length) if pre_length.abs > 0.001

      t = VBO::ShapeForge::PickDistanceGetter.new(a_vec, ass_chain, po, pre_length)
      t.prefix = "Span End Setback"
      t.state = 1
      t.action = ->(tool){
        p1,p2 = [tool.ip1, tool.ip2].map{|c| c.position}
        vec = p1.vector_to(p2)
        distance = vec.samedirection?(a_vec) ? p1.distance(p2) : - p1.distance(p2)
        @assembly.fence.spans[value.split('Span')[1].to_i].end_setback += distance
        self.refresh(@assembly)
        model.start_operation("Change Span End Setback", true)
        self.apply
        model.commit_operation
        model.tools.pop_tool
        refresh(@assembly, value)
      }
      model.tools.push_tool t
    end
  end
end
