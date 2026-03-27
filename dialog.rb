Sketchup.require File.join(File.dirname(__FILE__), 'main')
Sketchup.require File.join(File.dirname(__FILE__), 'dialog_merge')
Sketchup.require File.join(File.dirname(__FILE__), 'manager')
Sketchup.require File.join(File.dirname(__FILE__), 'pro_actions')

module VBO::ShapeForge
  class Dialog1
    attr_accessor :dialog, :members, :temp_pinned, :no_profile
    attr_reader :temp_profile
    def initialize
      @temp_profile = nil
      @no_profile = VBO::ShapeForge::Shape.new('No_Selection -6.168108031190741 -3.5611588321986645 -5.7486757261177885 -4.107773654359008 -5.0362391182600845 -5.0362391182600845 -3.5611588321986645 -6.168108031190734 -1.8433914568161356 -6.879630575076217 0.0 -7.122317664397329 1.8433914568161285 -6.879630575076217 3.5611588321986645 -6.168108031190737 5.0362391182600845 -5.036239118260088 6.168108031190734 -3.561158832198668 6.879630575076213 -1.8433914568161391 7.122317664397329 0.0 6.87963057507622 1.8433914568161285 6.431774200730231 2.9246123897574527 6.168108031190741 3.561158832198661 5.7486757261177885 4.107773654359004 5.0362391182600845 5.0362391182600845 3.5611588321986645 6.168108031190734 1.8433914568161356 6.879630575076217 0.0 7.122317664397329 -1.8433914568161356 6.879630575076217 -3.5611588321986645 6.168108031190737 -5.0362391182600845 5.0362391182600845 -6.168108031190734 3.5611588321986645 -6.87963057507622 1.8433914568161356 -7.122317664397329 0.0 -6.87963057507622 -1.843391456816132 -6.4317742007302385 -2.924612389757449|4.151951783500948 3.1859046562676525 -4.835050258113398 -2.002743391666101 -5.098716427652889 -1.3661969492248893 -5.2785796682146255 0.0 -5.098716427652889 1.3661969492248929 -4.5713840885739 2.6392898341073128 -3.732519478427996 3.7325194784279994 -2.639289834107309 4.5713840885739 -1.3661969492248929 5.098716427652889 0.0 5.2785796682146255 1.3661969492249 5.098716427652885 2.6392898341073163 4.571384088573897 3.732519478428003 3.732519478427996|-3.732519478427996 -3.732519478427996 -4.151951783500948 -3.1859046562676525 4.835050258113398 2.002743391666101 5.098716427652889 1.3661969492248893 5.2785796682146255 0.0 5.098716427652889 -1.3661969492248893 4.5713840885739 -2.639289834107309 3.732519478428003 -3.732519478427996 2.6392898341073163 -4.571384088573897 1.3661969492248929 -5.098716427652889 0.0 -5.2785796682146255 -1.3661969492248858 -5.098716427652889 -2.639289834107309 -4.5713840885739|extended|5|false|0.0|0.0|0.0|30.0|1.0|1.0|2|Default|Layer0')
      @multi_profile = VBO::ShapeForge::Shape.new('MultiProfiles_Selection -20.275590551181097 -14.707820620578365 -20.275590551181097 -20.275590551181107 -14.70782062057836 -20.275590551181107 0.0 -5.56776993060274 14.707820620578374 -20.27559055118111 20.275590551181097 -20.275590551181107 20.275590551181097 -14.70782062057837 5.567769930602736 -3.552713678800501e-15 20.275590551181097 14.707820620578364 20.275590551181097 20.275590551181107 14.707820620578367 20.275590551181114 0.0 5.56776993060274 -14.707820620578374 20.275590551181114 -20.275590551181097 20.275590551181107 -20.275590551181097 14.707820620578378 -5.567769930602736 -3.552713678800501e-15|extended|5|false|0.0|0.0|0.0|30.0|1.0|1.0|2|Default|Layer0')
      @skip_adjust_size = false
      @dom_ready = false
      @pending_scripts = []
    end

    def temp_profile=(profile)
      @temp_profile = profile
      unless profile.nil?
        run_script(%Q{
          temp_material_name = '#{profile.material_name}';
          temp_layer_name = '#{
            Sketchup.version.to_i.ceil > 19 ?  profile.layer_name.gsub('Layer0','Untagged') : profile.layer_name
          }';
        })
      end
    end

    def get_members
      sel = Sketchup.active_model.selection.to_a
      @members = sel.find_all{|c| Identify.profile_member?(c)}.to_a
      if @members.empty?
        tool = Sketchup.active_model.tools.active_tool
        if tool.to_s.include?("VBO::ShapeForge::PTool")
          @members = tool.selection.to_a.flatten
        else
          @members = []
        end
      end
    end

    def profile
      sel = Sketchup.active_model.selection.to_a
      ps = if sel.empty?
        @members = []
        ""
      else
        get_members
        if @members.empty?
          faces = sel.find_all{|c| c.is_a?(Sketchup::Face)}
          if faces.length == 1
            self.temp_profile = VBO::ShapeForge::Shape.new(faces[0])
            #@temp_profile.preview(VBO::ShapeForge.profile_dialog.dialog, nil, '#ff0000')
            return @temp_profile
          else
            ""
          end
        else
          @members.group_by{|c|
            ForgeElement.new(c).profile.to_s
          }.max_by{|k,v| v.length}
        end
      end
      self.temp_profile = if ps != ""
        ForgeElement.new(ps[1][0]).profile
      else
        nil
      end
      @temp_profile
    end

    def update_profile

    end

    def color_to_hex(color)
      '#' + ('%02x%02x%02x' % Sketchup::Color.new(color).to_a).upcase
    end

    def html
      options = Options.new
      path = File.dirname(__FILE__)
      %Q{<!DOCTYPE html>
				<html>
				<head>
          <meta charset="utf-8"/>
          <script type='text/javascript' src='#{path}/lib/jquerry.js'></script>
          <script type='text/javascript' src='#{path}/lib/w2ui.min copy.js'></script>

          <script type='text/javascript' src='#{path}/lib/wz_jsgraphics.js'></script>
          <script type='text/javascript' src='#{path}/lib/two.js'></script>
          <script type='text/javascript' src='#{path}/lib/jquery.atwho.js'></script>
          <script type='text/javascript' src='#{path}/lib/jquery.caret.js'></script>
          <script src="https://kit.fontawesome.com/ad57bfaf8c.js" crossorigin="anonymous"></script>

          <link rel='stylesheet' type='text/css' href='#{path}/lib/w2ui.css'/>
          <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.css">
          <link rel='stylesheet' type='text/css' href='#{path}/lib/jquery.atwho.css'/>
          <style>
      html, body {
        margin: 0;
        padding: 0;
      }
      /* Make w2ui toolbar flush to the edges */
      #settings .w2ui-toolbar {
        border: none !important;
        padding: 0 !important;
        margin: 0 !important;
      }
      #settings .w2ui-toolbar .w2ui-toolbar-left,
      #settings .w2ui-toolbar .w2ui-toolbar-right,
      #settings .w2ui-toolbar .w2ui-toolbar-middle {
        padding: 0 !important;
        margin: 0 !important;
      }
      #settings .w2ui-toolbar .w2ui-tb-group,
      #settings .w2ui-toolbar .w2ui-tb-button,
      #settings .w2ui-toolbar .w2ui-tb-spacer,
      #settings .w2ui-toolbar .w2ui-tb-break,
      #settings .w2ui-toolbar .w2ui-tb-menu,
      #settings .w2ui-toolbar .w2ui-scroll-left,
      #settings .w2ui-toolbar .w2ui-scroll-right {
        margin: 0 !important;
      }
      #headImg {
        margin: 0;
        padding: 0;
        width: 100%;
      }
      #headImg img {
        display: block; /* remove inline-gap */
        margin: 0;
      }
            #floatToolbar {
                position: fixed;
                top: 330px; /* Đặt nó ở giữa theo chiều dọc của dialog */
                left: -180px; /* Đặt nó sát bên trái của dialog */
                transform: translateY(-50%) rotate(90deg); /* Điều chỉnh lại cho đúng vị trí và quay 90 độ */
                transform-origin: center;
                width: 420px; /* Điều chỉnh theo nhu cầu của bạn */
                height: 28px;
                margin: auto;
                background-color: white;
                border-radius: 4px;
                /* box-shadow: 0 0 10px 0 rgb(110 110 110 / 20%); */
                z-index: 100;
            }
          </style>
			  </head>
				<body onresize="sketchup.resize(getDivBoundingBox('body'));place_toolbar('settings');">
        <div id="headImg" >
					<img src="#{path}/images/header.png" alt="Head Image" width="auto" height="45px" >
				</div>
          <div id="settings" style="padding: 0; margin: 0;"></div>
          <div id="profile_info" style="padding: 35px 8px 0px 40px;">
            <center>
            <div id="profile_header" style="width:100%">

              <h4 id = "profile_name" contenteditable="true" class = "selective" title="Shape Name" style="font-family: Sans-serif; text-align: center;color: #3078a0;font-size:18px;padding: 2px 8px; margin: 0; line-height: 1.5;" ></h4>

            </div>
            <div id="Canvas" style="position:relative;height:250px;width:72%;margin-top:40px;">
              <div id="Radios" style="z-index:100;">
                <input hidden type="radio" id="radio_0" name="aligntment" value="6"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(0);" onmouseleave="radio_over(0)">

                <input hidden type="radio" id="radio_1" name="aligntment" value="7"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(1);" onmouseleave="radio_over(1)">

                <input hidden type="radio" id="radio_2" name="aligntment" value="8"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(2);" onmouseleave="radio_over(2)">

                <input hidden type="radio" id="radio_3" name="aligntment" value="3"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(3);" onmouseleave="radio_over(3)">

                <input hidden type="radio" id="radio_4" name="aligntment" value="4"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(4);" onmouseleave="radio_over(4)">

                <input hidden type="radio" id="radio_5" name="aligntment" value="5"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(5);" onmouseleave="radio_over(5)">

                <input hidden type="radio" id="radio_6" name="aligntment" value="0"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(6);" onmouseleave="radio_over(6)">

                <input hidden type="radio" id="radio_7" name="aligntment" value="1"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(7);" onmouseleave="radio_over(7)">

                <input hidden type="radio" id="radio_8" name="aligntment" value="2"  style="width: 14px;height:14px;cursor: pointer;z-index:100;opacity:0.8;" onmouseenter="radio_hover(8);" onmouseleave="radio_over(8)">
              </div>
              <div id = "Dims" style="z-index:101;">
                <span hidden contenteditable="true"  class="dim selective selective" id = "width" onmouseenter="dim_hover('width');" onmouseleave="dim_over('width');" >width</span>

                <span hidden contenteditable="true"  class="dim selective" id = "height" onmouseenter="dim_hover('height');" onmouseleave="dim_over('height');">height</span>

                <span hidden contenteditable="true"  class="dim selective" id = "x_offset" onmouseenter="dim_hover('x_offset');" onmouseleave="dim_over('x_offset');">x offset</span>

                <span hidden contenteditable="true"  class="dim selective" id = "y_offset" onmouseenter="dim_hover('y_offset');" onmouseleave="dim_over('y_offset');">y offset</span>

                <span hidden contenteditable="true"  class="dim selective" id = "rotation" onmouseenter="dim_hover('rotation');" onmouseleave="dim_over('rotation');">rotation</span>


                </div>
                  <img id="origin" hidden class="imgs" src="#{path}/images/dialog/origin.bmp" width="13" height="13">

                  <img id="mirror" hidden class="imgs" src="#{path}/images/dialog/mirror.bmp" width="25" height="19">

                  <span hidden class = "transaction btn"  id="undo" onclick="sketchup.action('undo');" onmouseenter="btn_hover('undo');" onmouseleave="btn_over('undo');"><img src="#{path}/images/icons/tb-undo.png" width="13" height="13"></span>

                  <span hidden class = "transaction btn" id="redo" onclick="sketchup.action('redo');" onmouseenter="btn_hover('redo');" onmouseleave="btn_over('redo');"><img src="#{path}/images/icons/tb-redo.png" width="13" height="13"></span>

                  <span hidden class = "transaction btn "  id="material_name" onclick="sketchup.action('material_name');" onmouseenter="btn_hover('material_name');" onmouseleave="btn_over('material_name');"><img src="#{path}/images/icons/mat_tool.png" width="13" height="13"></span>

                  <span hidden class = "transaction btn " id="layer_name" onclick="sketchup.action('layer_name');" onmouseenter="btn_hover('layer_name');" onmouseleave="btn_over('layer_name');"><img src="#{path}/images/icons/lay_tool.png" width="13" height="13"></span>

                  <div id="floatToolbar">
                    <div hidden id="profile_toolbar" class="imgs"></div>
                  </div>
                  <div hidden id="member_toolbar"class="ximgs"></div>


                </div>

              </center>

            </div>
            <div hidden id="selective" style="width: 90%;height: 130px;"></div>

          <script type="text/javascript">
            var jg = new jsGraphics("Canvas");

            var profile_color = "#AAAAAA";
            var fill_color = "#CCCCCC";
            var bg_color = "#FFFFFF";
            var rotation_color = "#2092E3";
            var temp_color = "";
            var temp_order = "";
            var temp_font_size="";
            var mirror = false;
            var selective_top = 300;

            var temp_material_name = '';
            var temp_layer_name = '';
            var  material_list = #{( [Sketchup.active_model.materials.unique_name("Default")] + Sketchup.active_model.materials.map{|c| c.name}).to_json};
            var layer_list = #{( Sketchup.active_model.layers.map{|c| c.display_name}).to_json};

            #{self.js_functions_divs}
            #{self.js_functions_canvas}
            #{self.js_functions_toolbars}
            function getDivBoundingBox(divSelector) {
                const $div = $(divSelector);
                if (!$div.length) {
                    return null; // Trả về null nếu div không tồn tại
                }

                let minTop = Number.MAX_VALUE;
                let minLeft = Number.MAX_VALUE;
                let maxRight = Number.MIN_VALUE;
                let maxBottom = Number.MIN_VALUE;

                // Duyệt qua tất cả các thành phần con
                $div.find('*').each(function() {
                    const $child = $(this);
                    if ($child.is(':visible')) { // Chỉ xét các phần tử hiển thị
                        const offset = $child.offset(); // Lấy vị trí tương đối so với document
                        const width = $child.outerWidth();
                        const height = $child.outerHeight();

                        // Cập nhật các giá trị bounding box
                        minTop = Math.min(minTop, offset.top);
                        minLeft = Math.min(minLeft, offset.left);
                        maxRight = Math.max(maxRight, offset.left + width);
                        maxBottom = Math.max(maxBottom, offset.top + height);
                    }
                });

                // Nếu không có phần tử con nào hiển thị, trả về bounding box của chính div
                if (minTop === Number.MAX_VALUE || minLeft === Number.MAX_VALUE) {
                    const offset = $div.offset();
                    return {
                        top: offset.top,
                        left: offset.left,
                        width: $div.outerWidth(),
                        height: $div.outerHeight()
                    };
                }

                // Trả về kết quả bounding box
                return {
                    top: minTop,
                    left: minLeft,
                    width: maxRight - minLeft,
                    height: maxBottom - minTop
                };
            }

            $(function () {
              $('.transaction').css('display','none');
              // common variables

              // settings toolbar

              $('#settings').w2toolbar(#{self.toolbar_settings});

              place_toolbar("settings");

              //Canvas

              $("#mirror").click(function(){
                mirror = !mirror
                if (mirror) {
                  show_tooltip($("#mirror"),"Mirrored");
                  $(this).css('background-color',"red");
                } else {
                  show_tooltip($("#mirror"),"Not mirrored");
                  $(this).css('background-color',"white");
                }
                sketchup.change('mirror');
              });

              $('input:radio[name="aligntment"]').change(
                function(){
                  if ($(this).is(':checked')) {
                    for (var i = 0; i < 9; i++) {
                      var j
                      switch (i) {
                        case 0:
                        case 1:
                        case 2:
                          j = i + 6;
                          break;
                        case 3:
                        case 4:
                        case 5:
                          j = i;
                          break;
                        case 6:
                        case 7:
                        case 8:
                          j = i - 6;
                          break;
                      }
                      if (i == $(this).val()) {
                        radio_hover(j);
                      } else {
                        radio_over(j);
                      }
                    }
                    sketchup.change('placement', $(this).val())
                  }
                }
              );

              var profile_name = $("#profile_name").text();
              $("#profile_name").keydown(function(e) {
                if (e.keyCode === 13) {
                  e.preventDefault();
                  $(this).blur();
                }
              });
              $("#profile_name").blur(function() {
                if (profile_name!=$("#profile_name").text()){
                  profile_name = $("#profile_name").text();
                  sketchup.change('name',profile_name, 'profile_name')
                }
              });

              var rotation = $("#rotation").text();
              $("#rotation").blur(function() {
                if (rotation!=$("#rotation").text()){
                  rotation = $("#rotation").text();
                  sketchup.change('rotation',rotation)
                }
              });

              // profile_toolbar
              $('#profile_toolbar').w2toolbar(#{self.toolbar_profile});

              // members toolbar
              $('#member_toolbar').w2toolbar(#{self.toolbar_member});
              place_toolbar("member_toolbar");
              // keep member toolbar centered on window resize
              $(window).on('resize', function(){
                place_toolbar('member_toolbar');
              });

              // material name
              $('#material_name').click(function(event){

                var html = `<div id="material_input" style="padding: 10p"><input id="mat" type="text" placeholder = "${temp_material_name}"></div>`;

                $('#material_name').w2overlay({
                    name: 'material_name',
                    html: html,
                });
                $('#mat').w2field('combo', {
                  items: material_list,
                  match: 'contains',
                });
                $('#mat').change(function(event) {
                  var selectedOption = $(this).data('selected');
                  if (selectedOption) {
                    if (selectedOption.text) {
                      temp_material_name = selectedOption.text;
                    } else {
                      temp_material_name =  $('#mat').val();
                    }
                    sketchup.change('material_name', temp_material_name);
                    $('#w2ui-overlay-material_name').remove();
                  }
                });
                $('#mat').focus();
              });

              // layer name

              $('#layer_name').click(function(event){

                var html = `<div id="layer_input" style="padding: 10p"><input id="lay" type="text" placeholder = "${temp_layer_name}"></div>`;

                $('#layer_name').w2overlay({
                    name: 'layer_name',
                    html: html,
                });
                $('#lay').w2field('combo',{
                  items: layer_list,
                  match: 'contains',

                  });
                $('#lay').change(function(event) {

                  var selectedOption = $(this).data('selected');
                  if (selectedOption) {
                    if (selectedOption.text) {
                      temp_layer_name = selectedOption.text;
                    } else {
                      temp_layer_name =  $('#lay').val();
                    }
                    sketchup.change('layer_name', temp_layer_name, 'layer_name');
                    $('#w2ui-overlay-layer_name').remove();
                  }
                });
                $('#lay').focus();
              });

              document.addEventListener("contextmenu", function(event) {
                event.preventDefault();
              });

              if (window.sketchup && typeof sketchup.ready === 'function') {
                sketchup.ready();
              }
            });
          </script>
				</body>
				</html>
      }
    end

    def visible?
      @dialog && @dialog.visible?
    end

    def close_dialog
      @dialog.close if @dialog
    end

    def show_dialog
      @dialog.show
    end

    def refresh(i = nil)
      if i == 1 || i.nil?
        # puts "refresh #{@i}"
        self.profile
        redraw
      end
    end

    def redraw(box = nil)
      if  @temp_profile
        run_script(%Q{
          w2ui.member_toolbar.enable('select_member');
          w2ui.settings.enable('save');
        })

        if @temp_profile.rotation == 0
          run_script(%Q{
            w2ui.profile_toolbar.disable('project_profile')
          })
        else
          run_script(%Q{
            w2ui.profile_toolbar.enable('project_profile')
          })
        end

        get_members
        options = Options.new
        if options.pinned
          if !@members.empty?
            compare = @members.map{|c| ForgeElement.new(c).profile}
            enable_items = [
              "'path_functions'",
              "'path_functions:reverse'",
              "'path_functions:close'",
              "'split'",
              "'split:normal'",
              "'split:miter'",
              "'split:butt'",
              "'project_member'"
            ]
            if @members.length == 2
              enable_items += [
                "'path_functions:join-normal'",
                "'path_functions:join-miter'",
                "'path_functions:join-butt'",
              ]
            end

            run_script(%Q{
              w2ui.profile_toolbar.enable('append', 'apply', 'select_apply', 'project_profile', 'edit_profile', 'apply_flask');

              w2ui.member_toolbar.enable(#{enable_items.join(',')});

              if (w2ui.profile_toolbar.get('select_apply').checked && $('#selective').css('display') == 'none') {
                w2ui.profile_toolbar.click('select_apply');
                w2ui.profile_toolbar.click('select_apply');
              }
            })
          else
            compare = nil
            if @temp_pinned
              @temp_pinned = nil
              options.pinned = false
              options.save
              run_script(%Q{
                disable_pinned();
              })
            end
            run_script(%Q{
              $('#selective').css('display','none');
              w2ui.member_toolbar.enable('select_member');
              w2ui.member_toolbar.uncheck('select_member');
              w2ui.profile_toolbar.enable('pinned');

              w2ui.profile_toolbar.disable('append', 'apply', 'apply_flask', 'select_apply', 'project_profile', 'edit_profile');

              w2ui.member_toolbar.disable('split', 'path_functions','project_member', 'joint_shape_forge');
            })
            if Sketchup.active_model.selection.to_a.any?{|e| e.is_a?(Sketchup::Edge) || e.is_a?(Sketchup::Face)}
              run_script(%Q{
                w2ui.profile_toolbar.enable('apply', 'apply_flask');
              })
            end
          end
          @temp_profile.preview(@dialog, compare)

        else
          @temp_profile.preview(@dialog)
          if !@members.empty?
            enable_items = [
              "'path_functions'",
              "'path_functions:reverse'",
              "'path_functions:close'",
              "'split'",
              "'split:normal'",
              "'split:miter'",
              "'split:butt'",
              "'project_member'"
            ]
            if @members.length == 2
              enable_items += [
                "'path_functions:join-normal'",
                "'path_functions:join-miter'",
                "'path_functions:join-butt'",
                "'joint_shape_forge'",
              ]
            end
            run_script(%Q{
              w2ui.member_toolbar.enable(#{enable_items.join(',')});
            })
          else
            run_script(%Q{
              $('#selective').css('display','none');
             w2ui.member_toolbar.enable('select_member');

              w2ui.member_toolbar.disable('split', 'path_functions','project_member', 'joint_shape_forge');
            })
          end
        end
        tool = Sketchup.active_model.tools.active_tool
        if tool.to_s.include?("VBO::ShapeForge::PTool")
          tool.temp_profile =  @temp_profile
        end
      else
        @no_profile.preview(@dialog, nil, '#ff0000')
        run_script(%Q{
          //clearCanvas();
          w2ui.member_toolbar.disable('split', 'path_functions','select_member', 'project_member', 'joint_shape_forge');
          w2ui.settings.disable('save');
          //$('#selective').css('display','none');
          //w2ui.member_toolbar.enable('select_member');
          //w2ui.member_toolbar.uncheck('select_member');
        })
      end
      run_script("sketchup.adjust_size(getDivBoundingBox('body'));") unless @skip_adjust_size
    end

    def run_script(script)
      if @dialog && self.visible? && @dom_ready
        @dialog.execute_script(script)
      elsif @dialog
        @pending_scripts << script
      end
    end

    def flush_pending_scripts
      return unless @dialog && @dom_ready
      @pending_scripts.each do |script|
        @dialog.execute_script(script)
      end
      @pending_scripts.clear
    end

    def on_dialog_ready(_payload = nil)
      return if @dom_ready
      @dom_ready = true
      flush_pending_scripts
      refresh
      activate_magic_wand
      activate_pinned
    end

    def activate_magic_wand
      run_script(%Q{w2ui.settings.check('magic');})
      action('magic', true)
    end

    def activate_pinned
      run_script(%Q{w2ui.profile_toolbar.check('pinned');})
      action('pinned', true)
    end

    def create_dialog
      @dom_ready = false
      @pending_scripts = []
      VBO::ShapeForge.enable_shapeforge_sel_observer
      VBO::ShapeForge.enable_dialog_tool_observer
      VBO::ShapeForge.enable_lay_ob
      VBO::ShapeForge.enable_mat_ob
      VBO::ShapeForge.enable_overlay
      op = Options.new
      if op.click_edit
        VBO::ShapeForge.enable_click_edit_observer
      else
        VBO::ShapeForge.enable_dialog_undo_observer
      end

      if op.scale_rebuild
        VBO::ShapeForge.enable_scale_tool_observer
      end

      VBO::ShapeForge.enable_shapeforge_unit_observer
      @dialog = UI::HtmlDialog.new(
        dialog_title:  "SketchupHome",
        scrollable: true,
        height: 680, #790
        min_height: 450, #600
        width: 360, #425
        min_width: 290, #380
        left: 100,
        top: 100,
        resizable: true,
        preferences_key: 'profile.fun.dialog1'
      )
      @dialog.set_on_closed(){
        VBO::ShapeForge.disable_shapeforge_sel_observer
        VBO::ShapeForge.disable_dialog_undo_observer
        VBO::ShapeForge.disable_dialog_tool_observer
        VBO::ShapeForge.disable_scale_tool_observer
        VBO::ShapeForge.disable_click_edit_observer
        VBO::ShapeForge.disable_shapeforge_unit_observer
        VBO::ShapeForge.disable_lay_ob
        VBO::ShapeForge.disable_mat_ob
        VBO::ShapeForge.disable_overlay
        Sketchup.active_model.selection.clear
        op = Options.new
        op.pinned = false
        op.save
        if @profile_connect
          @profile_connect.close
          @profile_connect = nil
        end
        VBO::ShapeForge.profile_dialog = nil
        @dialog = nil
        @dom_ready = false
        @pending_scripts.clear

      }
      @dialog.add_action_callback("resize"){|a,c|
        @skip_adjust_size = true
        begin
          self.redraw
        ensure
          @skip_adjust_size = false
        end
      }
      @dialog.add_action_callback("ready"){|a,c|
        on_dialog_ready(c)
      }
      @dialog.add_action_callback("adjust_size"){|a,c|
        # puts "adjust callback triggered #{c}"
        w, h = @dialog.get_size
        @dialog.set_size(w, c["height"] + c["top"] + 65)
        #run_script("place_toolbar('settings')")
      }
      @dialog.add_action_callback("change"){|a,c,v, d|
        # puts "changed callback triggered #{c} : #{v}"
        change(c,v, d)
      }
      @dialog.add_action_callback("action"){|a,c,v|
        # puts "action callback triggered #{c} : #{v}"
        action(c,v)
      }
      @dialog.add_action_callback("call"){|a,c,v|
        # puts "action callback triggered #{c} : #{v}"
        action(c,v)
      }
      @dialog.set_html html
      # @dialog.set_url("https://product-connect.com/product")
      # @dialog.set_file File.join(__dir__, 'ui/html/index.html')

      @dialog.show
    end

    def change(command,value, from)
      # puts "change #{command} : #{value} - from #{from}"
      Sketchup.active_model.start_operation("ShapeForge Edit", true)
      get_members
      @members = [nil] if @members.to_a.empty?

      @members.each{|i|
        if i
          pm = ForgeElement.new(i)
        else
          pm = nil
        end
        case command
        when "name"
          @temp_profile.name = value.gsub("\n","%20").gsub(" ","%20")
        when 'placement'
          #if pm
          #  pm.set_from_profile! @temp_profile
          #  pm.placement_point = value.to_i + 1
          #  @temp_profile.set_from_profile_member pm
          #else
            @temp_profile.placement_point = value.to_i + 1
          #end
        when 'mirror'
          if pm && !Options.new.pinned
            pm.mirror!
            @temp_profile.set_from_profile_member pm
          else
            @temp_profile.mirror = !@temp_profile.mirror
          end
        when "rotation"
          if pm && !Options.new.pinned
            pm.rotation = value.to_i
            @temp_profile.set_from_profile_member pm
          else
            @temp_profile.rotation = value.to_i
          end
        when 'width'

          if value.to_f > 0
            width = @temp_profile.default_width
            # UI.messagebox(width)
            @temp_profile.x_scale = value.to_s.to_l.to_f / width
          end
        when 'height'
          if value.to_f > 0
            height = @temp_profile.default_height
            @temp_profile.y_scale = value.to_s.to_l.to_f / height
          end
        when 'x_offset'
          @temp_profile.x_offset = value.to_s.to_l.to_f
        when 'y_offset'
          @temp_profile.y_offset = value.to_s.to_l.to_f
        when "smooth_angle"
          @temp_profile.smooth_angle = value
        when "material_name"
          # UI.messagebox(value)
          if (value.downcase.strip == 'default')
            if pm  && !Options.new.pinned
              i.material = nil
              pm.material_name = 'default'
            end
            @temp_profile.material_name = value.strip
          else
            mat_name = value.strip
            mat = Sketchup.active_model.materials[mat_name]
            if mat.nil?
              mat = Sketchup.active_model.materials.add(mat_name)
              mat.color = VBO::ShapeForge.random_sketchup_color
            end
            if pm && !Options.new.pinned
              i.material = mat
              pm.material_name = mat.name
            end
            @temp_profile.material_name = mat.name
          end
        when "layer_name"
          s = value.strip.gsub('*_*', ' ').gsub("%20", " ")
          lay =  Sketchup.active_model.layers.add(s)
          if pm && !Options.new.pinned
            i.layer = lay
          end
          @temp_profile.layer_name = lay.display_name
        end
        redraw
        if pm && !Options.new.pinned
          pm.set_from_profile! @temp_profile
        else
          run_script(%Q{
						if ( $('#selective').css('display') == 'block' &&  $('#selective').css('border-color') == "rgb(255, 0, 0)") {
							$('#clear').click();
              w2ui.profile_toolbar.disable('apply', 'apply_flask');
						}
					})
        end
      }
      @members.reject!{|x| x.nil?}
      pline_tool = Sketchup.active_model.tools.active_tool
      if pline_tool.is_a?(VBO::ShapeForge::PlineTool)
        # UI.messagebox("Please exit the tool and re-enter to apply changes")
        pline_tool.obj.profile = @temp_profile
      end
      Sketchup.active_model.commit_operation
      VBO::ShapeForge.manager_need_reload
    end

    def uncheck(s)
      toolbar, item = s.split('|')
      run_script(%Q{w2ui.#{toolbar}.uncheck('#{item}');})
    end

    def check(s)
      toolbar, item = s.split('|')
      run_script(%Q{w2ui.#{toolbar}.check('#{item}');})
    end

    def call_profile_connect
      if @profile_connect
        @profile_connect.close
        @profile_connect = nil
        return
      end

      @profile_connect = UI::HtmlDialog.new(
        dialog_title:  "Shapes Connect",
        scrollable: true,
        height: 600,
        width: 800,
        left: 200,
        top: 200,
        resizable: true,
        preferences_key: "shape.fun.connect"
      )
      @profile_connect.set_on_closed(){
        @profile_connect = nil
      }
      @profile_connect.add_action_callback("ready"){|add_action_callback |
				@profile_connect.execute_script(<<~JS
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
          JS
        )
      }
      @profile_connect.add_action_callback("loadmodel") { |action_context, id, mode|
			pm_skuc = defined?(VBO::ShapeForge) ? VBO::ShapeForge : nil
			# pm_toolbox = defined?(Toolbox::VBO::ShapeForge) ? Toolbox::VBO::ShapeForge : nil
			if mode == "profile"
				# Default code, use or delete...
				mod = Sketchup.active_model # Open model
				ent = mod.entities # All entities in model
				sel = mod.selection # Current selection

				if pm_skuc && VBO::ShapeForge.profile_dialog

					profile_dialog = VBO::ShapeForge.profile_dialog
					skp = load_file_form_web(id)

					profile_dialog.temp_profile = VBO::ShapeForge::Shape.new(skp)

					profile_dialog.temp_profile.preview(profile_dialog.dialog)
					Sketchup.active_model.start_operation("ProfilesToy - Apply Profile", true)
					profile_dialog.get_members
					profile_dialog.members.each{|i|
						pm = VBO::ShapeForge::ForgeElement.new(i)
						pm.set_from_profile!(profile_dialog.temp_profile)
					}
					Sketchup.active_model.commit_operation

					VBO::ShapeForge.manager_need_reload
					# VBO::ShapeForge.magic
				else
					load_component(id)
				end
      else
				load_component(id)
			end
		}
      @profile_connect.set_url"https://system.sketchupthai.com/samrtobj/smart-object-profile_mvp.php"
      #@profile_connect.set_url"https://system.sketchupthai.com/samrtobj/index-profile.php"
      #@profile_connect.set_url"https://sketchuphome.com/smart%20object/"
      # @profile_connect.set_url"https://system.sketchupthai.com/samrtobj/index.php?mode=Profile"
      @profile_connect.set_position(100, 50)
      @profile_connect.show
    end

    def load_file_form_web(id)
      require 'open-uri'
      url = "https://system.sketchupthai.com/samrtobj/obj/#{id}.skp"

      download_path = File.join(File.dirname(__FILE__), 'product', 'profile.skp')

      if File.exist?(download_path)
        # puts "Deleting existing file"
        FileUtils.rm(download_path)
      end

      # ดาวน์โหลดไฟล์ SKP จาก URL
      URI.open(url) do |skp_file|
        # อ่านไฟล์ SKP เป็น binary
        skp_data = skp_file.read

        # บันทึกไฟล์ SKP ลงในเครื่อง
        File.open(download_path, 'wb') do |file|
            file.write(skp_data)
        end
        end

      return download_path
    end

    def load_component(url)
      model = Sketchup.active_model


      loadmodel = "https://system.sketchupthai.com/samrtobj/obj/"+url+'.skp'
      #loadmodel = "https://sketchuphome.com/smart%20object/obj/"+ url + ".skp"

      loads = model.definitions.load_from_url(loadmodel)
      te = model.place_component(loads)
    end
  end
end
