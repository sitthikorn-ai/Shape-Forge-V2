Sketchup.require File.join(File.dirname(__FILE__), 'dialog')
Sketchup.require File.join(File.dirname(__FILE__), 'forge_structure')
Sketchup.require File.join(File.dirname(__FILE__), 'options')
Sketchup.require File.join(File.dirname(__FILE__), 'fences')
Sketchup.require File.join(File.dirname(__FILE__), 'methods')
Sketchup.require File.join(File.dirname(__FILE__), 'main')
Sketchup.require File.join(File.dirname(__FILE__), 'posts_n_rails')
Sketchup.require File.join(File.dirname(__FILE__), 'member')
# Sketchup.require File.join(File.dirname(__FILE__), 'assembly_controller')
class VBO::ShapeForge::Dialog1

  def action(command, value)
    options = VBO::ShapeForge::Options.new
    case command
    when 'magic'
      if value
        VBO::ShapeForge.magic
      else
        Sketchup.active_model.tools.pop_tool
      end
    when 'click_edit'
      options.click_edit = value
      if value
        VBO::ShapeForge.disable_click_edit_observer
        VBO::ShapeForge.enable_click_edit_observer
        VBO::ShapeForge.disable_dialog_undo_observer
      else
        VBO::ShapeForge.disable_click_edit_observer
        VBO::ShapeForge.enable_dialog_undo_observer
      end
      options.save
    when 'scale_rebuild'
      options.scale_rebuild = value
      if value
        VBO::ShapeForge.disable_scale_tool_observer
        VBO::ShapeForge.enable_scale_tool_observer
      else
        VBO::ShapeForge.disable_scale_tool_observer
      end
      options.save
    when 'delete_edges'
      options.delete_edges = value
      options.save
    when 'report'
      VBO::ShapeForge.manager
    when 'set_smooth_angle'
      @temp_profile.smooth_angle = value.to_f
      Sketchup.active_model.start_operation("Shape Forge - Smooth Angle", true)
      get_members
      @members.each{|i|
        i.make_unique if i.is_a?(Sketchup::Group)
        pm = VBO::ShapeForge::ForgeElement.new(i)
        pm.set_from_profile!(@temp_profile)
      }
      Sketchup.active_model.commit_operation
    when 'smooth_angle'
      run_script(%Q{
        w2prompt({
          label: 'Smooth Angle',
          value: #{@temp_profile ? @temp_profile.smooth_angle : 60},
          attrs: 'style="width: 100px"',
          title: 'Smooth Angle',
          ok_text: 'OK',
          cancel_text: 'Cancel',
          width: 300,
          height: 200,
          callBack: function (value) {
            if (value) {
              sketchup.action('set_smooth_angle', value);
            }
          }
        });
      })

    when 'extrude_mode'
      # UI.messagebox "Extrude mode: #{value}"
      if value
        @temp_profile.extrude_mode = "normal_mode"
      else
        @temp_profile.extrude_mode = "follow_me_mode"
      end
      unless options.pinned
        Sketchup.active_model.start_operation("Shape Forge - Extrude Mode", true)
        get_members
        @members.each{|i|
          i.make_unique if i.is_a?(Sketchup::Group)
          member = VBO::ShapeForge::ForgeElement.new(i)
          member.set_from_profile!(@temp_profile)
        }
        Sketchup.active_model.commit_operation
        redraw
        VBO::ShapeForge.manager_need_reload
      end
    when 'select_member'
      if value
        sel = Sketchup.active_model.active_entities
        @active_members = sel.find_all{|c|
          VBO::ShapeForge::Identify.profile_member?(c)
        }
        if @temp_profile && !options.pinned
          @temp_pinned = true
          options.pinned = true
          options.save
        end
        run_script(%Q{
          w2ui.profile_toolbar.disable('select_apply');
          enable_pinned();
          w2ui.profile_toolbar.disable('pinned');
          show_selective(
            function(){
              $(`#selective`).css(`display`,`none`);
              w2ui.member_toolbar.uncheck(`select_member`);
              w2ui.profile_toolbar.enable('select_apply');
            },
            function (event) {
              event.onComplete = function(){
                sketchup.action('select_member_change', w2ui.selective.record);
              };
            }
          );
          sketchup.action('select_member_change', w2ui.selective.record);
        })
      else
        if @temp_pinned
          @temp_pinned = nil
          options.pinned = false
          options.save
          run_script(%Q{
            disable_pinned();
          })
        end
        run_script(%Q{
          w2ui.profile_toolbar.enable('pinned');
          $('#selective').css('display','none');

        })
        if options.pinned
          run_script("w2ui.profile_toolbar.enable('select_apply');")
        end
      end
    when 'select_member_change'
      #puts value.to_s
      sel = Sketchup.active_model.active_entities
        @active_members = sel.find_all{|c|
          VBO::ShapeForge::Identify.profile_member?(c)
        }
      keys = value.keys.find_all{|c| value[c]}
      #UI.messagebox keys
      unless keys.empty?
        if options.pinned
          #puts @active_members
          @active_members.reject!{|m|
            pm = VBO::ShapeForge::ForgeElement.new(m)
            prf = pm.profile
            keys.find{|v|
              @temp_profile.send(v) != prf.send(v)
            }
          }
          #puts @active_members
        else
        end
      else

      end
      VBO::ShapeForge.disable_shapeforge_sel_observer
      Sketchup.active_model.selection.clear
      VBO::ShapeForge.enable_shapeforge_sel_observer
      Sketchup.active_model.selection.add @active_members
    when 'object_to_forge'
      VBO::ShapeForge.object_to_shape_forge
    when 'pinned'
      #puts command, value
      options.pinned = value

      if value
        get_members
        run_script(%Q{
          enable_pinned();
        }) if !@members.empty?
      else
        VBO::ShapeForge.enable_shapeforge_sel_observer
        VBO::ShapeForge.profile_dialog.refresh if VBO::ShapeForge.profile_dialog_visible?
        run_script(%Q{
          disable_pinned();
        })
      end
      options.save
    when 'apply'
      Sketchup.active_model.start_operation("ShapeForge - Apply Shape", true)
      get_members
      @members.each{|i|
        i.make_unique if i.is_a?(Sketchup::Group)
        pm = VBO::ShapeForge::ForgeElement.new(i)
        pm.set_from_profile!(@temp_profile)
      }
      sel = Sketchup.active_model.selection.to_a.reject{|c| !Sketchup.active_model.active_entities.to_a.include?(c)} - @members
      if !sel.empty?
        g = VBO::ShapeForge::Graph.new(sel)
        sg = g.create_graph_from_simplified_graph(g.simply_graph)
        # puts sg.edges.to_s
        longest_paths = sg.merge_edges_to_polylines(sg.edges)
        longest_paths.each{|edge|
           pm = VBO::ShapeForge::ForgeElement.add(sel[0].parent.entities, edge)
           pm.set_from_profile!(@temp_profile)
        }
        if VBO::ShapeForge::Options.new.delete_edges
          sel.each{|i| i.erase!}
        end
      end
      Sketchup.active_model.commit_operation
      redraw
      VBO::ShapeForge.manager_need_reload
    when 'apply_flask'
      Sketchup.active_model.start_operation("ShapeForge - Apply Shape", true)
      get_members
      @members.each{|i|
        i.make_unique if i.is_a?(Sketchup::Group)
        pm = VBO::ShapeForge::ForgeElement.new(i)
        pm.set_from_profile!(@temp_profile)
      }
      sel = Sketchup.active_model.selection.to_a.find_all{|c| c.is_a?(Sketchup::Edge)}
      unless sel.empty?
        g = VBO::ShapeForge::Graph.new(sel)
        g.simply_graph.each{|edge|
           pm = VBO::ShapeForge::ForgeElement.add(sel[0].parent.entities, edge)
           pm.set_from_profile!(@temp_profile)
        }
      end
      Sketchup.active_model.commit_operation
      redraw
      VBO::ShapeForge.manager_need_reload
    when 'display_selective_fields'
      # puts "display_selective_fields"
      get_members
      selected_profiles = @members.map{|i|
        pm = VBO::ShapeForge::ForgeElement.new(i)
        pm.profile
      }
      record = value
      value.each{|k, v|
        if selected_profiles.uniq{|pr| pr.send(k)}.size == 1 && selected_profiles[0].send(k) == v
          record[k] = true
        else
          record[k] = false
        end
      }
      run_script(%Q{
        console.log('display_selective_fields');
        w2ui.selective.record = #{record.to_json};
        w2ui.selective.refresh();
        Object.keys(w2ui.selective.record).forEach(function(key){
          var temp = w2ui.selective.get(key);
          if (temp) {
            $(`#${key}`).prop('disabled', true);
          }
        });
      });
    when 'select_apply'
      if value

        run_script(%Q{
          w2ui.member_toolbar.disable('select_member');
          w2ui.profile_toolbar.disable('apply');
          show_selective(
            function(){
              $(`#selective`).css(`display`,`none`);
              w2ui.profile_toolbar.uncheck(`select_apply`);
              w2ui.member_toolbar.enable('select_member');
              //console.log('release selective apply');
              if (w2ui.member_toolbar.get('select_member').checked) {
                w2ui.member_toolbar.click('select_member');
                w2ui.member_toolbar.click('select_member');
              }
            },
            function (event) {
              event.onComplete = function(){
                sketchup.action('select_apply_change', w2ui.selective.record);
              };
            },
            false
          );
          sketchup.adjust_size(getDivBoundingBox('body'));
        })
      else
        run_script(%Q{
          $('#selective').css('display','none');
          w2ui.member_toolbar.enable('select_member');
          w2ui.profile_toolbar.enable('apply');
          if (w2ui.member_toolbar.get('select_member').checked) {
            w2ui.member_toolbar.click('select_member');
            w2ui.member_toolbar.click('select_member');
          }
          sketchup.adjust_size(getDivBoundingBox('body'));
        })
      end
    when 'select_apply_change'
      get_members
      keys = value.keys.find_all{|c| value[c]}
      #UI.messagebox keys
      unless keys.empty?
        if options.pinned
          Sketchup.active_model.start_operation("ShapeForge - Selective Apply Shape")
          @members.each{|i|
            i.make_unique if i.is_a?(Sketchup::Group)
            member = VBO::ShapeForge::ForgeElement.new(i)
            member_profile = member.profile

            keys.each{|k|
              # puts %Q{
              #   --------
              #   key: #{k}
              #   member: #{member_profile.send(k)}
              #   will be replaced by
              #   temp: #{@temp_profile.send(k)}
              # }
              case k
              when 'fullname'
                member_profile.name =  @temp_profile.name
                member_profile.points = @temp_profile.points
                #  t.w = t.dw * t.x
                # m.w = m.dw * m.x = t.dw * t.x
                # m.x = t.dw * t.x / m.dw = t.w / m.dw
                member_profile.x_scale = @temp_profile.width / member_profile.default_width
                member_profile.y_scale = @temp_profile.height / member_profile.default_height
              else
                member_profile.instance_variable_set("@#{k}".to_sym, @temp_profile.send(k))
              end
            }
            member.set_from_profile!(member_profile)
            member.update_trim
          }
          Sketchup.active_model.commit_operation
          redraw
          VBO::ShapeForge.manager_need_reload
          run_script(%Q{w2ui.profile_toolbar.click('select_apply');})
        else
        end
      else
      end
    when 'append'
      #puts 'append'
      Sketchup.active_model.start_operation("ShapeForge -Append Shape")
      get_members
      @members.each{|i|
        i.make_unique if i.is_a?(Sketchup::Group)
        member = VBO::ShapeForge::ForgeElement.new(i)
        chain = member.chain.path.map{|c| c.transform(i.transformation )}
        pm = VBO::ShapeForge::ForgeElement.add(Sketchup.active_model.active_entities, chain)
        pm.set_from_profile!(@temp_profile)
      }
      Sketchup.active_model.commit_operation
      redraw
      VBO::ShapeForge.manager_need_reload
    when 'save'
      fullname = "#{@temp_profile.name} - #{@temp_profile.width.to_l} x #{@temp_profile.height.to_l}.skp"
      # puts fullname
      skp = UI.savepanel("Save Shape", "", VBO::ShapeForge.correct_filename(fullname))
      @temp_profile.save_skp(skp) if skp
    when 'load'
      skp = UI.openpanel("Load ProfileBuilder's Shape", "", "SketchUp Files|*.skp||")
      if skp
          self.temp_profile = VBO::ShapeForge::Shape.new(skp)

          @temp_profile.preview(@dialog)
          Sketchup.active_model.start_operation("ShapeForge - Apply Shape", true)
          get_members
          @members.each{|i|
            i.make_unique if i.is_a?(Sketchup::Group)
            pm = VBO::ShapeForge::ForgeElement.new(i)
            pm.set_from_profile!(@temp_profile)
          }
          Sketchup.active_model.commit_operation
          VBO::ShapeForge.manager_need_reload
      end
    when 'undo'
      Sketchup.send_action("editUndo:")
      VBO::ShapeForge.manager_need_reload
    when 'redo'
      Sketchup.send_action("editRedo:")
      VBO::ShapeForge.manager_need_reload
    when 'junction_style:continuous', 'junction_style:normal', 'junction_style:miter_joint', 'junction_style:butt_joint'
      js_value = command.split(':')[1]
      @temp_profile.junction_style = js_value
      tool = Sketchup.active_model.tools.active_tool
      if tool.to_s.include?("VBO::ShapeForge::PTool")
        tool.temp_profile = @temp_profile
      end
      icon_map = { 'continuous' => 'icon-split-continuous', 'normal' => 'icon-split-normal', 'miter_joint' => 'icon-split-miter', 'butt_joint' => 'icon-split-butt' }
      js_icon = icon_map[js_value] || 'icon-split-continuous'
      run_script(%Q{
        var item = w2ui.member_toolbar.get('junction_style');
        item.img = '#{js_icon}';
        item.items.forEach(function(sub) {
          sub.selected = (sub.id === '#{js_value}');
        });
        w2ui.member_toolbar.refresh();
      })
    when 'split:miter', 'split:normal', 'split:butt'
      Sketchup.active_model.start_operation("ShapeForge - Miter Joints Split", true)
      get_members
      gcs = []
      com = case command
      when 'split:miter'
        'miter_joint'
      when 'split:butt'
        'butt_joint'
      when 'split:normal'
        'normal'
      end
	      @members.each{|i|
	        i.make_unique if i.is_a?(Sketchup::Group)
	        pm = VBO::ShapeForge::ForgeElement.new(i)
	        result = pm.draw(com)
	        gcs += Array(result).compact
	      }
      VBO::ShapeForge.disable_shapeforge_sel_observer
      Sketchup.active_model.selection.clear
      VBO::ShapeForge.enable_shapeforge_sel_observer
      Sketchup.active_model.selection.add gcs

      Sketchup.active_model.commit_operation
      VBO::ShapeForge.manager_need_reload
    when "trim_plane"
      if value
        t = VBO::ShapeForge::TrimToPlane.new
        Sketchup.active_model.tools.push_tool t
      else
        Sketchup.active_model.tools.pop_tool
      end
      VBO::ShapeForge.manager_need_reload
    when "trim_solid"
      if value
        t = VBO::ShapeForge::TrimToSolid.new
        Sketchup.active_model.tools.push_tool t
      else
        Sketchup.active_model.tools.pop_tool
      end
      VBO::ShapeForge.manager_need_reload
    when "path_functions:reverse", "reverse"
      Sketchup.active_model.start_operation("ShapeForge - Reverse Member", true)
      get_members
      @members.each{|i|
        i.make_unique if i.is_a?(Sketchup::Group)
        pm = VBO::ShapeForge::ForgeElement.new(i)
        profile = pm.profile
        profile.set_from_profile_member(pm)
        pm.reverse
        profile.set_from_profile_member(pm)
        pm.set_from_profile!(profile, false)
      }
      Sketchup.active_model.commit_operation
      VBO::ShapeForge.manager_need_reload
    when "path_functions:close", "close"
      Sketchup.active_model.start_operation("ShapeForge - Close/Open Chain", true)
      get_members
      @members.each{|i|
        i.make_unique if i.is_a?(Sketchup::Group)
        pm = VBO::ShapeForge::ForgeElement.new(i)
        chain = pm.chain
        path = chain.path
        if chain.closed_path?
            path.pop
        else
            path << chain[0]
        end
        pm.set_chain path
        pm.draw
      }
      Sketchup.active_model.commit_operation
      VBO::ShapeForge.manager_need_reload
    when 'project_member:to_model_axes'
      Sketchup.active_model.start_operation("ShapeForge - Project Members", true)
      get_members
      @members.each{|i|
        i.make_unique if i.is_a?(Sketchup::Group)
        pm = VBO::ShapeForge::ForgeElement.new(i)
        pm.re_coordinate(pm.transformation, pm.transformation.inverse)
      }
      Sketchup.active_model.commit_operation
    when 'project_member:by_member'
      Sketchup.active_model.start_operation("ShapeForge - Project Members", true)
      get_members
      @members.each{|i|
        i.make_unique if i.is_a?(Sketchup::Group)
        pm = VBO::ShapeForge::ForgeElement.new(i)
        pm.re_coordinate(pm.transformation)
      }
      Sketchup.active_model.commit_operation
    when 'draw_profile'
      prof = VBO::ShapeForge::ProfileDraw.new(@temp_profile, @dialog)
      tool = VBO::ShapeForge::PlineTool.new(prof)
      tool.action = ->(t){
        t.obj.apply_junction_style
        t.obj.kill
        run_script(%Q{
           w2ui.profile_toolbar.uncheck('draw_profile')
        })
      }
      tool.snap = ->(view, tool){
        pos = tool.instance_variable_get(:@pos)
        path = tool.instance_variable_get(:@path)
        return[nil, nil, nil] if pos.nil? ||  pos[0] != ALT_MODIFIER_MASK || path.nil?
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
      Sketchup.active_model.tools.push_tool tool
    when 'material_name'
    when 'layer_name'
    when 'home'
    when 'path_functions:join-normal', 'path_functions:join-miter', 'path_functions:join-butt'
      Sketchup.active_model.start_operation("ShapeForge - Join Members", true)
      get_members
      profile = @temp_profile
      mems = @members.map{|c|
        pm = VBO::ShapeForge::ForgeElement.new(c)
        pm.chain.path.map{|pt|
          pt.transform(c.transformation)
        }.each_cons(2).to_a
      }

      type = case command
      when  'path_functions:join-normal'
        'continuous'
      when 'path_functions:join-miter'
        'miter_joint'
      when 'path_functions:join-butt'
        'butt_joint'
      end

      g = VBO::ShapeForge::Graph.new(mems.flatten(1))
      sg = g.create_graph_from_simplified_graph(g.simply_graph)
      # puts sg.edges.to_s
      longest_paths = sg.merge_edges_to_polylines(sg.edges)
      longest_paths.each{|edge|
          pm = VBO::ShapeForge::ForgeElement.add(Sketchup.active_model.active_entities, edge)
          pm.set_from_profile!(@temp_profile, type)
      }
        @members.each{|c| c.erase!}
      Sketchup.active_model.commit_operation
      VBO::ShapeForge.manager_need_reload
    when 'project_profile'
      pr = @temp_profile
      outer_loop = pr.get_transformed_loop(pr.outer_loop)
      pp = pr.clone
      pp.points = outer_loop
      pp.rotation= 0
      @temp_profile = pp
      self.redraw
    when 'stamp_profile'
      defs = Sketchup.active_model.definitions
      name =defs.unique_name(@temp_profile.fullname)
      d = defs.add(name)
      @temp_profile.draw(d.entities)
      Sketchup.active_model.place_component d
    when 'profile_connect'
      call_profile_connect
    else
      UI.messagebox "#{command.gsub(':','|')} - #{value}\nUnder Construction. Coming Soon"
      run_script(%Q{
        var temp = w2ui.member_toolbar.get('#{command}');
        if (temp) {
          w2ui.member_toolbar.uncheck('#{command}');
        }
        temp = w2ui.profile_toolbar.get('#{command}');
        if (temp) {
          w2ui.profile_toolbar.uncheck('#{command}');
        }
      });
    end
  end
end
