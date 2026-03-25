Sketchup.require File.join(File.dirname(__FILE__), 'dialog')
Sketchup.require File.join(File.dirname(__FILE__), 'forge_structure')
Sketchup.require File.join(File.dirname(__FILE__), 'options')
Sketchup.require File.join(File.dirname(__FILE__), 'fences')
Sketchup.require File.join(File.dirname(__FILE__), 'methods')
Sketchup.require File.join(File.dirname(__FILE__), 'main')
Sketchup.require File.join(File.dirname(__FILE__), 'posts_n_rails')
Sketchup.require File.join(File.dirname(__FILE__), 'member')
# Sketchup.require File.join(File.dirname(__FILE__), 'assembly_controller')
module VBO::ShapeForge
  class ForgeStructureController
    def js_functions_canvas
      %Q{
        function clearCanvas(){
          jg.clear();
          $('input:radio[name="aligntment"]').hide();
          $('.dim').css('display','none');
          $('.imgs').css('display','none');
          $('.transaction').css('display','none');
          $('#profile_name').css('display','none');
        }


        function drawProfile(xpoints,ypoints, compare = false, pcolor = ''){
          if (compare) {
            //var color = increase_brightness('#{color_to_hex(Sketchup.active_model.rendering_options["HighlightColor"].to_a)}', 60)
            var color = 'orange';
            jg.setStroke(2);
            jg.setColor(color);
          } else {
            if (pcolor == '') {
              jg.setColor(fill_color);
              jg.fillPolygon(xpoints,ypoints);
              jg.setStroke(2);
              jg.setColor(profile_color);
            } else {
              jg.setColor(increase_brightness(pcolor, 50));
              jg.fillPolygon(xpoints,ypoints);
              jg.setStroke(2);
              jg.setColor(pcolor);
            }
          }
          jg.drawPolygon(xpoints,ypoints);
          //jg.paint();
        }

        function increase_brightness(hex, percent){
          // strip the leading # if it's there
          hex = hex.replace(/^\s*#|\s*$/g, '');

          // convert 3 char codes --> 6, e.g. `E0F` --> `EE00FF`
          if(hex.length == 3){
              hex = hex.replace(/(.)/g, '$1$1');
          }

          var r = parseInt(hex.substr(0, 2), 16),
              g = parseInt(hex.substr(2, 2), 16),
              b = parseInt(hex.substr(4, 2), 16);

          return '#' +
            ((0|(1<<8) + r + (256 - r) * percent / 100).toString(16)).substr(1) +
            ((0|(1<<8) + g + (256 - g) * percent / 100).toString(16)).substr(1) +
            ((0|(1<<8) + b + (256 - b) * percent / 100).toString(16)).substr(1);
        }

        function drawPolyline(xpoints,ypoints, compare = false){
          if (compare){
            //var color = ('#{color_to_hex(Sketchup.active_model.rendering_options["HighlightColor"].to_a)}')
            var color = 'orange';
            jg.setStroke(2);
            jg.setColor(color);
          } else {
            jg.setStroke(2);
            jg.setColor(profile_color);
          }
          jg.drawPolyline(xpoints,ypoints);
          //jg.paint();
        }

        function drawArc(x,y,alpha,radius){
          radius = parseInt(radius);
          //console.log([x,y,radius]);
          var delta = alpha / 24;
          var x_points = [x];
          var y_points = [y - radius];
          var p = [];

          for (let i = 1; i < 25; i++) {
            p = [
              parseInt(x - radius * Math.sin(delta * i * Math.PI / 180)),
              parseInt(y - radius * Math.cos(delta * i * Math.PI / 180))
            ]
            if (i == 24) {
              if (Math.round(Math.abs(alpha)) == 90 || Math.round(Math.abs(alpha)) == 270) {p[1] = y}
              if (Math.round(Math.abs(alpha)) == 180) {p[0] = x}
            }
            x_points.push(p[0]);
            y_points.push(p[1]);
          }
          jg.setStroke(1);
          jg.setColor(rotation_color);
          jg.drawPolyline(x_points,y_points);

          jg.setStroke(1);
          jg.drawLine(x,y,x_points[x_points.length - 1],y_points[y_points.length - 1]);
          jg.drawLine(x,y,x_points[0], y_points[0]);
          jg.fillEllipse(x_points[0] -2, y_points[0] - 2, 4, 4);
          jg.fillEllipse(x_points[x_points.length - 1] - 2, y_points[y_points.length - 1] - 2, 4, 4);



          if (alpha == 0){
            $("#rotation").html(`<i class="fa fa-undo fa-lg"></i><br>0`);
          } else {
            $("#rotation").text(`${alpha}°`);
          }

          var lx = $("#rotation").width();
          var ly = $("#rotation").height();

          $("#rotation").css({
            display: 'block',
            top: y - (radius + 11) * Math.cos(delta * 12 * Math.PI / 180) - ly/2,
            left: x - (radius + 11) * Math.sin(delta * 12 * Math.PI / 180) - lx/2,
            position:'absolute',
            transform: `rotate(${parseInt(- alpha / 2)}deg)`,
            'font-size': 14,
            'font-family': 'Arial',
            'font-weight': 'bold',
            'text-alignment': 'center',
            'z-index': 101,
            color: rotation_color
          });
        }

        function drawHole(xpoints,ypoints, pcolor = ''){
          if (pcolor == '') {
            jg.setColor(bg_color);
            jg.fillPolygon(xpoints,ypoints);
            jg.setStroke(2);
            jg.setColor(profile_color);
            jg.drawPolygon(xpoints,ypoints);
          } else {
            jg.setColor(bg_color);
            jg.fillPolygon(xpoints,ypoints);
            jg.setStroke(2);
            jg.setColor(pcolor);
            jg.drawPolygon(xpoints,ypoints);
          }
          //jg.paint();

        }

        function drawOrigin(x,y){
          jg.setColor("red");
          jg.fillEllipse(x, y, 8, 8);
          //jg.paint();
        }
        function drawPoint(x,y){
          jg.setColor("#555555");
          jg.fillEllipse(x, y, 8, 8);
          //jg.paint();
        }
        function place_toolbar(id,top=null){
          if (top) {
            $(`#${id}`).css('top',top)
          }
          var len = 0;
          w2ui[id].items.forEach(function(c){
            if (c.type == 'break'){
              len += 0.6
            } else if (c.type == 'spacer'){
              len += 0.5
            } else if (c.type == 'menu'){
              len += 1.5
            } else if (c.type == 'menu-check'){
              len += 3
            } else {
              len += 1
            }
          });
          var sc = len * 28 / $(`#${id}`).parent().width();
          $(`#${id}`).css({
            position:'absolute',
            display: 'block',
            //width: `${sc * 100}%`,
            left: ($(`#${id}`).parent().width() * (1-sc))/2 + 7,
            'background-color': 'white',
          });
          $(`#settings`).css({
            padding-left: '8px'
          });
        }
      }
    end
  end
  class Dialog1
    def js_functions_divs
      %Q{
        function get_align(i){
          var alignment = ["Top - Left", "Top - Midle", "Top - Right", "Midle - Left", "Center", "Midle - Right", "Bottom - Left", "Bottom - Midle", "Bottom - Right"];
          return alignment[parseInt(i)];
        }

        function enable_pinned(){
          w2ui.profile_toolbar.check('pinned');
          w2ui.profile_toolbar.enable('append', 'apply', 'select_apply', 'stamp_profile', 'project_profile');
        }

        function disable_pinned(){
          w2ui.profile_toolbar.uncheck('pinned');
          w2ui.profile_toolbar.disable('append', 'apply', 'select_apply', 'stamp_profile', 'project_profile');
        }

        function get_dim_pos(id){
          var dim_pos = {
            "width": 'Shape Width',
            "height": 'Shape Height',
            "x_offset": 'X Offset',
            "y_offset": 'Y Offset',
            "rotation":  'Rotation'
          }
          return dim_pos[id]
        }

        function show_selective(source,func,fullname = true){
          $('#selective').w2destroy('selective');
          $('#selective').w2form(#{self.form_selective});
          //selective_top = $('#selective').css('top');

          if (fullname){
            w2ui.selective.fields.forEach(function(c){
              w2ui.selective.record[c.field] = (c.field == 'fullname');
            });
          } else {
            w2ui.selective.fields.forEach(function(c){
              w2ui.selective.record[c.field] = false;
            });
          }
          w2ui.selective.refresh();
          w2ui.selective.onChange = func;
          $("#selective").css({
            display: 'block',
            top: selective_top,
            left: ($('body').width() + 10 - $("#selective").width())* 0.5,
            margin: 'auto',
            position:'absolute',
            'z-index': 102,
          });
          if ($('button[id="all"]').length == 0) {
            var clickonbutt = '';
            if (fullname) {
              clickonbutt = 'sketchup.action(`select_member_change`, w2ui.selective.record);'
            } else {
              //sketchup.action('display_selective_fields', w2ui.selective.record);
              clickonbutt = 'sketchup.action(`select_apply_change`, w2ui.selective.record);'
            }
            $('#selective').append(
              '<br><button class="btn" id= "all" style="position: absolute;right: 5px;" onclick="w2ui.selective.fields.forEach(c => w2ui.selective.record[c.field] = true);w2ui.selective.refresh();$(`#cancel`).click('+ source +');'+ clickonbutt +'">All</button>'
            );
            $('#cancel').click(source);
          }
          if (fullname){
            $('#selective').find('label').css('color','#468fcd');

            $('#selective').find('.btn').css({
              'color':'#468fcd',
              'border-color':'#468fcd',
            });
            $('#selective').css('border-color','#468fcd');
          } else {
            $('#selective').css('border-color','red');
          }
        }

        function show_tooltip(id, text) {
          id.w2tag(text, {
            auto: true,
            maxWidth: 200,
            position: 'top|left|right|bottom',
            className: 'w2ui-light'
          });
        }

        function dim_hover(id){
          show_tooltip($(`#${id}`), get_dim_pos(id));
          temp_color = $(`#${id}`).css('color');
          $(`#${id}`).css('color','red');

          temp_order = $(`#${id}`).css('z-index');
          $(`#${id}`).css('z-index', 200);

          temp_font_size = $(`#${id}`).css('font-size');
          $(`#${id}`).css('font-size', 18);
        }
        function dim_over(id){
          show_tooltip($(`#${id}`), '');
          $(`#${id}`).css('color',temp_color);
          $(`#${id}`).css('z-index', temp_order);
          $(`#${id}`).css('font-size', temp_font_size);
        }

        function radio_hover(i){
          show_tooltip($(`#radio_${i}`), get_align($(`#radio_${i}`).val()));
        }
        function radio_over(i){
          show_tooltip($(`#radio_${i}`), '');
        }

        function btn_hover(i){
          var name = '';
          if (i.includes('do')) {
            show_tooltip($(`#${i}`), (i.charAt(0).toUpperCase() + i.slice(1)).split('_')[0]);
          } else {

            if (i.includes('material')) {
              name = temp_material_name
            } else {
              name = temp_layer_name
            }
            show_tooltip($(`#${i}`), (i.charAt(0).toUpperCase() + i.slice(1)).split('_')[0].replace('Layer', '#{
              Sketchup.version.to_i.ceil > 19 ? "Tag" : "Layer"
            }') + ': ' + name);
          }

        }
        function btn_over(i){
          show_tooltip($(`#${i}`), '');
        }


      }
    end

    def js_functions_canvas
      %Q{
        function clearCanvas(){
          jg.clear();
          $('input:radio[name="aligntment"]').hide();
          $('.dim').css('display','none');
          $('.imgs').css('display','none');
          $('.transaction').css('display','none');
          $('#profile_name').css('display','none');
        }


        function drawProfile(xpoints,ypoints, compare = false, pcolor = '', fcolor = ''){
          if (compare) {
            //var color = increase_brightness('#{color_to_hex(Sketchup.active_model.rendering_options["HighlightColor"].to_a)}', 60)
            var color = 'orange';
            jg.setStroke(2);
            jg.setColor(color);
          } else {
            if (pcolor == '') {
              jg.setColor(fill_color);
              jg.fillPolygon(xpoints,ypoints);
              jg.setStroke(2);
              jg.setColor(profile_color);
            } else {
              jg.setColor(increase_brightness(fcolor, 50));
              jg.fillPolygon(xpoints,ypoints);
              jg.setStroke(2);
              jg.setColor(pcolor);
            }
          }
          jg.drawPolygon(xpoints,ypoints);
          //jg.paint();
        }

        function increase_brightness(hex, percent){
          // strip the leading # if it's there
          hex = hex.replace(/^\s*#|\s*$/g, '');

          // convert 3 char codes --> 6, e.g. `E0F` --> `EE00FF`
          if(hex.length == 3){
              hex = hex.replace(/(.)/g, '$1$1');
          }

          var r = parseInt(hex.substr(0, 2), 16),
              g = parseInt(hex.substr(2, 2), 16),
              b = parseInt(hex.substr(4, 2), 16);

          return '#' +
            ((0|(1<<8) + r + (256 - r) * percent / 100).toString(16)).substr(1) +
            ((0|(1<<8) + g + (256 - g) * percent / 100).toString(16)).substr(1) +
            ((0|(1<<8) + b + (256 - b) * percent / 100).toString(16)).substr(1);
        }

        function drawPolyline(xpoints,ypoints, compare = false){
          if (compare){
            //var color = ('#{color_to_hex(Sketchup.active_model.rendering_options["HighlightColor"].to_a)}')
            var color = 'orange';
            jg.setStroke(2);
            jg.setColor(color);
          } else {
            jg.setStroke(2);
            jg.setColor(profile_color);
          }
          jg.drawPolyline(xpoints,ypoints);
          //jg.paint();
        }

        function drawArc(x,y,alpha,radius){
          radius = parseInt(radius);
          //console.log([x,y,radius]);
          var delta = alpha / 24;
          var x_points = [x];
          var y_points = [y - radius];
          var p = [];

          for (let i = 1; i < 25; i++) {
            p = [
              parseInt(x - radius * Math.sin(delta * i * Math.PI / 180)),
              parseInt(y - radius * Math.cos(delta * i * Math.PI / 180))
            ]
            if (i == 24) {
              if (Math.round(Math.abs(alpha)) == 90 || Math.round(Math.abs(alpha)) == 270) {p[1] = y}
              if (Math.round(Math.abs(alpha)) == 180) {p[0] = x}
            }
            x_points.push(p[0]);
            y_points.push(p[1]);
          }
          jg.setStroke(1);
          jg.setColor(rotation_color);
          jg.drawPolyline(x_points,y_points);

          jg.setStroke(1);
          jg.drawLine(x,y,x_points[x_points.length - 1],y_points[y_points.length - 1]);
          jg.drawLine(x,y,x_points[0], y_points[0]);
          jg.fillEllipse(x_points[0] -2, y_points[0] - 2, 4, 4);
          jg.fillEllipse(x_points[x_points.length - 1] - 2, y_points[y_points.length - 1] - 2, 4, 4);



          if (alpha == 0){
            $("#rotation").html(`<i class="fa fa-undo fa-lg"></i><br>0`);
          } else {
            $("#rotation").text(`${alpha}°`);
          }

          var lx = $("#rotation").width();
          var ly = $("#rotation").height();

          $("#rotation").css({
            display: 'block',
            top: y - (radius + 11) * Math.cos(delta * 12 * Math.PI / 180) - ly/2,
            left: x - (radius + 11) * Math.sin(delta * 12 * Math.PI / 180) - lx/2,
            position:'absolute',
            transform: `rotate(${parseInt(- alpha / 2)}deg)`,
            'font-size': 14,
            'font-family': 'Arial',
            'font-weight': 'bold',
            'text-alignment': 'center',
            'z-index': 101,
            color: rotation_color
          });
        }

        function drawHole(xpoints,ypoints, pcolor = ''){
          if (pcolor == '') {
            jg.setColor(bg_color);
            jg.fillPolygon(xpoints,ypoints);
            jg.setStroke(2);
            jg.setColor(profile_color);
            jg.drawPolygon(xpoints,ypoints);
          } else {
            jg.setColor(bg_color);
            jg.fillPolygon(xpoints,ypoints);
            jg.setStroke(2);
            jg.setColor(pcolor);
            jg.drawPolygon(xpoints,ypoints);
          }
          //jg.paint();

        }

        function drawOrigin(x,y){
          jg.setColor("red");
          jg.fillEllipse(x, y, 8, 8);
          //jg.paint();
        }
        function drawPoint(x,y){
          jg.setColor("#555555");
          jg.fillEllipse(x, y, 8, 8);
          //jg.paint();
        }

      }
    end
  end
end
