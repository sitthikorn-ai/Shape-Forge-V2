module VBO::ShapeForge::CoreAPI

  class PolyClickTool
    attr_accessor :paintcolor, :vertices, :action, :condition
    attr_reader :collect, :path, :pts

    def initialize(condition, action, paintcolor = Sketchup::Color.new('cyan'), vertices =  nil)
      @paintcolor = paintcolor
      @vertices = vertices
      @collect = []
      @condition = condition
      @action = action
      Sketchup::set_status_text "Length", SB_VCB_LABEL
      reset
    end
    def call_action(view)
      @action.call(@collect)
      reset
    end

    def condition(view)
      @condition.call(@path,@collect)
    end

    def collector(view, last_point = nil)
    end

    def call_collector(view)
      if condition(view)
        entities = collector(view)
        if entities.is_a?(Array)
          @collect += entities
        else
           @collect << entities
        end
      end
    end

    def stop?
       (@vertices && @pts.length > @vertices)
    end

    def reset
      @ip  = Sketchup::InputPoint.new
      @ip1 = Sketchup::InputPoint.new
      @ip2 = Sketchup::InputPoint.new
      Sketchup.active_model.active_view.invalidate
      @drawn = false
      @pts = []
      @path = nil
      @collect = []
      @hover_faces = []
    end

    def deactivate(view)
      view.invalidate unless @drawn
    end

    def onLButtonDown(flags, x, y, view)
    end

    def onLButtonUp(flags, x, y, view)
      @ip2.pick view, x, y, @ip1
      ph = view.pick_helper
      ph.do_pick(x, y)
      @path = ph.path_at(0)
      if condition(view)
        @pts << @ip2.position
        call_collector(view)
        call_action(view) if stop?
      else
        #Sketchup.active_model.tools.pop_tool
      end
    end

    def onCancel(reason, view)
      reset
    end

    def draw_path(view)
      VBO::ShapeForge::DRAWVIEW.draw_path3d(view, @pts, @paintcolor)
    end

    def draw_hover(view)
    end

    def draw_collect(view)
    end

    def draw(view)
      draw_path(view)
      draw_hover(view)
      draw_collect(view)
    end

    def onMouseMove(flags, x, y, view)
      Sketchup.set_status_text "#{@collect}"
      # Entity att pick
      ph = view.pick_helper
      ph.do_pick(x, y)
      @path = ph.path_at(0)
      # Point at pick
      @ip.pick view, x, y
      view.invalidate if( @ip.display? )
      @ip1.copy! @ip
      if condition(view)
        @hover_faces = collector(view,@ip1.position)
        @pts[0] = @ip1.position
        length = @pts[0].distance(@pts[-1])
        Sketchup::set_status_text length.to_s, SB_VCB_VALUE
        view.invalidate
      end
    end
    def onUserText(text, view)

      begin
        value = text.to_l
      rescue
        UI.beep
        # puts "Cannot convert #{text} to a Length"
        value = nil
        Sketchup::set_status_text "", SB_VCB_VALUE
      end
      return if !value

      pt1 = @pts[-1]
      vec = @pts[0] - pt1
      if( vec.length == 0.0 )
        UI.beep
        return
      end
      vec.length = value
      pt2 = pt1 + vec
      @pts << pt2
      call_action(view) if stop?
    end
    def onKeyDown(key, repeat, flags, view)
      if( key == CONSTRAIN_MODIFIER_KEY )
        @shift_down_time =true
        if( view.inference_locked? )
          view.lock_inference
        elsif @ip1.valid?
          view.lock_inference @ip1
        elsif @ip2.valid?
          view.lock_inference @ip2, @ip1
        end
      else
        case key
        when VK_UP, VK_LEFT, VK_RIGHT, VK_DOWN
          view.lock_inference if view.inference_locked?
        end
      end
    end
    def onKeyUp(key, rpt, flags, view)
      if( key == CONSTRAIN_MODIFIER_KEY && view.inference_locked? )
        @shift_down_time=nil
        view.lock_inference
      end
      case key
      when 17
        call_action(view)
      when 8
        @pts.pop if @pts.length > 1
      else
        #puts key
      end
      view.invalidate
    end
  end

  class ClickClick < PolyClickTool
    def initialize(action, paintcolor = Sketchup::Color.new('cyan'))
      @paintcolor = paintcolor
      @vertices = 2
      @ip  = Sketchup::InputPoint.new
      @ip1 = Sketchup::InputPoint.new
      @ip2 = Sketchup::InputPoint.new
      @collect = []
      @action = action
      Sketchup.active_model.active_view.invalidate
      reset
    end

     def call_action(view)
      @action.call(@pts)
      reset
    end

    def condition(view)
      true
    end
    def draw(view)
    end
    def onMouseMove(flags, x, y, view)
      # Entity att pick
      ph = view.pick_helper
      ph.do_pick(x, y)
      @path = ph.path_at(0)
      # Point at pick
      @ip.pick view, x, y
      view.invalidate if( @ip.display? )
      @ip1.copy! @ip
      if condition(view)
        @pts[0] = @ip1.position
        view.invalidate
      end
    end
    def onLButtonUp(flags, x, y, view)
      @ip2.pick view, x, y, @ip1
      ph = view.pick_helper
      ph.do_pick(x, y)
      @path = ph.path_at(0)
      if condition(view)
        @pts << @ip2.position
        call_action(view) if stop?
      else
      end
    end
  end

  class DialogName
  attr_accessor :dialog

    def initialize
    end

    def html()
      path = File.dirname(__FILE__)
      %Q{
        <html>
        <head>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/0.149.0/three.min.js" integrity="sha512-6p9lGA4Cm89KiwN1CixiOVQU2H9e13LeYoN6/Hj/qoUhtrMW5vNiqQz9Z96Z7/I8u89ghL6SPBz9na5HFVzF3g==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
        <script src="https://cdn.jsdelivr.net/npm/three-obj-loader@1.1.3/dist/index.min.js"></script>
          <script>
            window.onload = function() {
              // Set up the scene
              var scene = new THREE.Scene();
              var camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
              var renderer = new THREE.WebGLRenderer();
              renderer.setSize(window.innerWidth, window.innerHeight);
              document.body.appendChild(renderer.domElement);

              // Load the 3D model
              var loader = new THREE.OBJLoader();

              // Add an open dialog to choose the .obj file
              var input = document.createElement("input");
              input.type = "file";
              input.accept = ".obj";
              input.style.display = "none";
              document.body.appendChild(input);
              input.addEventListener("change", function(event) {
                var reader = new FileReader();
                reader.addEventListener("load", function(event) {
                  var contents = event.target.result;
                  var object = loader.parse(contents);
                  scene.add(object);
                });
                reader.readAsText(input.files[0]);
              });

              // Add a button to open the file dialog
              var button = document.createElement("button");
              button.textContent = "Open OBJ File";
              button.addEventListener("click", function() {
                input.click();
              });
              document.body.appendChild(button);

              // Add lights to the scene
              var ambientLight = new THREE.AmbientLight(0x404040);
              scene.add(ambientLight);

              var pointLight = new THREE.PointLight(0xffffff, 1, 100);
              pointLight.position.set(50, 50, 50);
              scene.add(pointLight);

              // Render the scene
              function render() {
                requestAnimationFrame(render);
                renderer.render(scene, camera);
              }
              render();
            };
          </script>
        </head>
        <body>
        </body>
      </html>


      }
    end

    def close
      @dialog.close
    end

    def visible?
      @dialog && @dialog.visible?
    end

    def run_script(script)
      @dialog.execute_script(script)
    end

    def show
      op = {
        dialog_title: "#{PLUGIN_NAME} - #{PLUGIN_VERSION}",
        scrollable: true,
        height: 500,
        width: 320,
        left: 150,
        top: 150,
        resizable: true,
        preferences_key: 'key'
      }
      @dialog = UI::HtmlDialog.new(op)
      @dialog.set_html(self.html())

      @dialog.set_on_closed{}

      @dialog.center
      @dialog.show
    end


  end
end	# module VBO::ShapeForge
