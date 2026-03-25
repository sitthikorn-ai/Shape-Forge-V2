Sketchup.require File.join(File.dirname(__FILE__), 'dialog')
Sketchup.require File.join(File.dirname(__FILE__), 'forge_structure')
Sketchup.require File.join(File.dirname(__FILE__), 'options')
Sketchup.require File.join(File.dirname(__FILE__), 'fences')
Sketchup.require File.join(File.dirname(__FILE__), 'methods')
Sketchup.require File.join(File.dirname(__FILE__), 'main')
Sketchup.require File.join(File.dirname(__FILE__), 'drawview')
Sketchup.require File.join(File.dirname(__FILE__), 'posts_n_rails')
Sketchup.require File.join(File.dirname(__FILE__), 'member')
# Sketchup.require File.join(File.dirname(__FILE__), 'assembly_controller')
module VBO::ShapeForge
  def self.manager
    if @profile_manager
      @profile_manager.manager.close unless @profile_manager.manager.nil?
      @profile_manager.manager = nil
      @profile_manager.call_manager
    else
      @profile_manager = Manager.new
    end
  end
  def self.manager_need_reload
    #profile_manager = VBO::ShapeForge.instance_variable_get(:@profile_manager)
    if @profile_manager && @profile_manager.manager
      @profile_manager.manager.execute_script("$('.w2ui-icon-reload').css('color','red');")
    end
  end
  class Manager
    attr_accessor :manager
    def initialize
      @columns = [
        "name",
        "width",
        "height",
        "placement_point",
        "mirror",
        "rotation",
        "x_offset",
        "y_offset",
        "smooth_angle",
        "material_name",
        "layer_name",
        "total_length",
        "total_volume",
        "largest_area"
      ]
      @captions = {"name"=>"Name", "width"=>"W", "height"=>"H", "placement_point"=>"Point", "mirror"=>"Mirror", "rotation"=>"Rot", "x_offset"=>"Ox", "y_offset"=>"Oy", "smooth_angle"=>"SM", "material_name"=>"Material", "layer_name"=>"Layer", "total_length"=>"Total Length", "total_volume" => "Total Volume", "largest_area" => "Largest Area"}

      @sortData = [{field: 'name', direction: 'desc'}]
      call_manager
    end

    def al
      ["Top - Left", "Top - Midle", "Top - Right", "Midle - Left", "Center", "Midle - Right", "Bottom - Left", "Bottom - Midle", "Bottom - Right"]
    end



    def create_records
      list = VBO::ShapeForge.model_members
      if list.empty?
        UI.messagebox "No Data!"
        return
      end
      records = []
      length = 0
      list.keys.each_with_index{|profile, i|
        total = list[profile].map{|k,v| v.map{|c| c.length}.inject(0){|sum,x| sum + x }}.inject(0){|sum,x| sum + x }
        tvol = list[profile].map{|k,v| v.map{|c| c.volume}.inject(0){|sum,x| sum + x }}.inject(0){|sum,x| sum + x }
        length += 1
        length += list[profile].values.length + list[profile].map{|k, v| v.length}.inject(0){|sum,x| sum + x }
        pf = VBO::ShapeForge::Shape.new(list[profile].keys[0])
        records << {
          recid: i,
          name: pf.name.gsub('*_*', ' ').gsub("%20", " "),
          width: pf.width.to_l.to_s.delete('~'),
          height: pf.height.to_l.to_s.delete('~'),
          total_length: total.to_l.to_s.delete('~'),
          total_volume: Sketchup.format_volume(tvol).delete('~'),
          largest_area: '',
          w2ui: {
            style: "color: black; font-weight: bold;",
            children: list[profile].map{|pro,mbs|
              pr = VBO::ShapeForge::Shape.new(pro)
              {
                recid: "#{i}-#{list[profile].keys.index(pro)}",
                name: pr.name.gsub('*_*', ' ').gsub("%20", " "),
                width: pr.width.to_l.to_s.delete('~'),
                height: pr.height.to_l.to_s.delete('~'),
                placement_point: al[pr.placement_point - 1],
                mirror: pr.mirror,
                rotation: pr.rotation,
                x_offset: pr.x_offset.to_l.to_s.delete('~'),
                y_offset: pr.y_offset.to_l.to_s.delete('~'),
                smooth_angle: pr.smooth_angle,
                material_name: pr.material_name,
                layer_name: pr.layer_name,
                total_length: mbs.map{|c| c.length}.inject(0){|sum,x| sum + x }.to_l.to_s.delete('~'),
                total_volume: Sketchup.format_volume(mbs.map{|c| c.volume}.inject(0){|sum,x| sum + x }).delete('~'),
                largest_area: '',
                pids: mbs.map{|c| c.definition.persistent_id},
                w2ui: {
                  style: "color: black; font-style: italic;",
                  children: mbs.map{|c|
                    prfil = c.profile
                    c.definition.instances.map{|ins|
                      {
                        recid: "#{i}-#{list[profile].keys.index(pro)}-#{c.definition.persistent_id}-#{ins.persistent_id}",
                        name: c.definition.group? ? c.name : "&lt;#{c.definition.name}> #{c.name}",
                        width: prfil.width.to_l.to_s.delete('~'),
                        height: prfil.height.to_l.to_s.delete('~'),
                        placement_point: al[prfil.placement_point - 1],
                        mirror: prfil.mirror,
                        rotation: prfil.rotation,
                        x_offset: prfil.x_offset.to_l.to_s.delete('~'),
                        y_offset: prfil.y_offset.to_l.to_s.delete('~'),
                        smooth_angle: prfil.smooth_angle,
                        material_name: prfil.material_name,
                        layer_name: prfil.layer_name,
                        total_length: c.length.to_l.to_s.delete('~'),
                        total_volume: Sketchup.format_volume(c.volume).delete('~'),
                        largest_area: Sketchup.format_area(c.largest_area).delete('~'),
                        pids: [c.definition.persistent_id],
                        w2ui: {
                          style: "color: brown; font-style: italic;"
                        }
                      }
                    }
                  }.flatten
                }
              }
            }
          }
        }
      }
      [records, length]
    end

    def create_columns
      captions = {"name"=>"Name", "width"=>"W", "height"=>"H", "placement_point"=>"Point", "mirror"=>"Mirror", "rotation"=>"Rot", "x_offset"=>"Ox", "y_offset"=>"Oy", "smooth_angle"=>"SM", "material_name"=>"Material", "layer_name"=>"Tag", "total_length"=>"Total Length", "total_volume" => "Total Volume", "largest_area" => "Largest Area"}
      sizes = ["166px", "57px", "54px", "69px", "47px", "32px", "55px", "52px", "40px", "69px", "52px", "103px", "88px", "101px"]
      al = ["left", "right", "right", "center", "center", "right", "right", "right", "right", "center", "center", "right", "right", "right"]
      edit = [
        { type: 'text'},
        { type: 'float'},
        { type: 'float'},
        { type: 'list', items:  self.al, match: 'contains'},
        { type: 'checkbox'},
        { type: 'float'},
        { type: 'float'},
        { type: 'float'},
        { type: 'float'},
        { type: 'list', items:  Sketchup.active_model.materials.to_a.map{|c| c.name}, match: 'contains'},
        { type: 'list', items:  Sketchup.active_model.layers.to_a.map{|c| c.name}, match: 'contains'},
        nil,
        nil,
        nil
      ]
      map = [
        "name",
        "width",
        "height",
        "placement_point",
        "mirror",
        "rotation",
        "x_offset",
        "y_offset",
        "smooth_angle",
        "material_name",
        "layer_name",
        "total_length",
        "total_volume",
        "largest_area"
      ].each_with_index.map{|c, i|
        { field: c, tooltip: c.gsub('_',' ').capitalize, caption: captions[c], size: sizes[i], editable: edit[i], sortable: true, searchable: true, style: "text-align: #{al[i]};"}
      }
      map
    end

    def save_to_excel(filename, workbooks)
      filename = "Untitle" if filename.to_s == ""
      code = %Q{
        var wb = XLSX.utils.book_new();
      }
      workbooks.each{|k,v|
        v.each{|c|
          c.delete_if{|key, value| value.nil?}
        }
        code += %Q{
        var wbx = XLSX.utils.json_to_sheet(#{v.to_json});
        XLSX.utils.book_append_sheet(wb, wbx, '#{k}');
        }
      }

      code +=  "XLSX.writeFile(wb, '#{filename}.xlsx');window.open('#{filename}.xlsx');"
      @manager.execute_script code
    end

    def call_manager
      if @manager
        @manager.close();
        @manager = nil
        return
      end
      records, length = create_records
      fields = create_columns
      dialog_height = [170 + (length + 4) * 25.4, 1100].min
      VBO::ShapeForge.enable_def_ob
      @op = {
        dialog_title: "#{PLUGIN_NAME} - #{PLUGIN_VERSION}",
        scrollable: true,
        height: dialog_height.to_i,
        width: 1000,
        left: 150,
        top: 150,
        resizable: false,
        preferences_key: 'profile.fun.manager'
      }

      code = %Q{<!DOCTYPE html>
        <html>
        <head>
          <script src="#{File.join(File.dirname(__FILE__),"lib/jquery-3.1.0.min.js")}"></script>
          <script type="text/javascript" src="#{File.join(File.dirname(__FILE__),"lib/w2ui.js")}"></script>
          <script type="text/javascript" src="#{File.join(File.dirname(__FILE__),"lib/xl.js")}"></script>
          <link rel="stylesheet" type="text/css" href="#{File.join(File.dirname(__FILE__),"lib/w2ui.css")}" />
        </head>
        <body oncontextmenu = "return false;">
        <div id="grid" style="width: 100%; height: #{dialog_height - 60 }px;"></div>
        <script type="text/javascript">
          $(function () {
            $("#grid").w2grid({
              name: "grid",
              header: "Model's Shapes Report",
              show: {
                toolbar: true,
                header: true,
                footer: true,
                toolbarAdd: false,
                toolbarDelete: false,
                toolbarSave: false,
                toolbarEdit: false,
                toolbarReload: true,
                toolbarSearch: true,
                toolbarColumns: true,
                lineNumbers: true,
              },
              textSearch: 'contains',
              fixedBody: true,
              multiSelect: true,
              onSort: function(event) {
                var grid = w2ui.grid;
                console.log(event);
                event.onComplete = function () {
                  if (event.field == 'level') {
                    var collator = new Intl.Collator(undefined, {numeric: true});
                    grid.records.sort((a, b) => collator.compare(a.level.replace('+','').replace('±','').replace(/,/g,''), b.level.replace('+','').replace('±','').replace(/,/g,'')));
                    if (event.direction == 'desc') {grid.records.reverse();}
                  }
                  grid.refresh();
                }
              },
              onSelect: function(event) {
                //console.log(w2ui.grid.getSelection());
                event.onComplete =  function() {
                  var visible = w2ui.grid.getSelection().map(c => w2ui.grid.get(c));
                  sketchup.select(visible, w2ui.grid.sortData);
                }
              },
              onUnselect: function(event) {
                event.onComplete =  function() {
                  var visible = w2ui.grid.getSelection().map(c => w2ui.grid.get(c));
                  sketchup.select(visible);
                }
              },

              onReload: function(event) {
                event.onComplete =  function() {
                   sketchup.reload();
                }
              },
              onChange: function(event) {
                event.onComplete =  function() {
                  var record = w2ui.grid.get(event.recid);
                  w2ui.grid.save();
                  w2ui.grid.refresh();
                  sketchup.edited(record, w2ui.grid.sortData);
                }
              },
              onDelete: function (event) {
                var visible = w2ui.grid.getSelection().map(c => w2ui.grid.get(c));
                console.log(visible);
                event.onComplete =  function() {
                  console.log(event);
                  sketchup.remove_pickers(visible, w2ui.grid.sortData)
                }
              },
              toolbar: {
                items: [
                  { type: 'break' },
                  { type: 'spacer' },

                  { type: 'button', id: 'preview_excel', caption: 'Excel', tooltip: 'Export To Excel(xlsx)', img: "icon-excel"},
                ],
                onClick: function (event) {
                  event.onComplete = function(){
                    switch (event.target) {
                      case 'preview_excel':
                        sketchup.excel_grid([w2ui.grid.columns, w2ui.grid.records]);
                        break;
                    }
                  };
                }
              },
              columns: #{fields.to_json},
              records: #{records.to_json}
            });
            w2ui['grid'].hideColumn('smooth_angle');
            w2ui.grid.records.filter(function(c){
              return !isNaN(c.recid);
            }).forEach(function(c){
              w2ui.grid.expand(c.recid);
            });
            w2ui.grid.records.forEach(function(c){
              if (c.w2ui.children != []) {
                w2ui.grid.expand(c.recid);
              }
            });
            w2ui.grid.on('expand', function(event) {
              event.onComplete = function(){
                sketchup.resize(w2ui.grid.records.length);
              };
            });
            w2ui.grid.on('collapse', function(event) {
              event.onComplete = function(){
                sketchup.resize(w2ui.grid.records.length);
              };
            });
            $('body').mouseleave(function() {
              //w2ui.grid.selectNone();
              var visible = w2ui.grid.getSelection().map(c => w2ui.grid.get(c));
              sketchup.mouse_out_manager(visible);
            });

            $('body').mouseenter(function() {
              var visible = w2ui.grid.getSelection().map(c => w2ui.grid.get(c));
              //sketchup.mouse_in_manager(visible);
              //sketchup.reload();

            });

          });
        </script>
        </body>
        </html>
      }

      @manager = UI::HtmlDialog.new @op
      @manager.set_html code
      @manager.add_action_callback("close"){ |action|
        @manager.close
        @manager = nil
      }
      @manager.set_on_closed {
        VBO::ShapeForge.disable_def_ob
        @manager = nil
      }


      @manager.add_action_callback("mouse_in_manager"){ |action, data|

      }

      @manager.add_action_callback("mouse_out_manager"){ |action, data|

      }

      @manager.add_action_callback("edited"){ |action, data|
        instances = []
        pids = data["pids"]
        pids = data["w2ui"]["children"].map{|c| c["pids"]}.flatten if pids.nil?
        pids.map{|c| Sketchup.active_model.find_entity_by_persistent_id(c)}.each{|c| instances += c.instances.to_a}
        fields = ["name", "width", "height", "placement_point",
          "mirror",
          "rotation",
          "x_offset",
          "y_offset",
          "smooth_angle",
          "material_name",
          "layer_name",
        ]
        Sketchup.active_model.start_operation("ShapeForge Report Edit", true)
        # puts instances
        instances.each{|i|
          fields.each{|f|
            # puts data[f]
            if data[f]
              field = data[f]
              field = field["id"] if field.is_a?(Array)
              pm = ForgeElement.new(i)
              profile = pm.profile
              profile.set_from_profile_member pm
              case f
              when "name"
                profile.name = field.gsub('<','').gsub('>','')
              when "width"
                width = profile.default_width
                profile.x_scale = field.to_s.to_l.to_f / width
              when "height"
                height = profile.default_height
                profile.y_scale = field.to_s.to_l.to_f / height
              when "mirror"
                pm.mirror!
                profile.set_from_profile_member pm
              when "rotation"
                pm.rotation = field
                profile.set_from_profile_member pm
              when "x_offset"
                profile.x_offset = field.to_s.to_l.to_f
              when "y_offset"
                profile.y_offset = field.to_s.to_l.to_f
              when "smooth_angle"
                profile.smooth_angle = field
              when "material_name"
                profile.material_name = field
                i.material = (field.downcase.strip == 'default') ?  nil : Sketchup.active_model.materials[field]
              when "layer_name"
                profile.layer_name = field
                i.layer = Sketchup.active_model.layers[field]
              when "placement_point"
                pm.placement_point = self.al.index(field) + 1
                profile.set_from_profile_member pm
              end
              pm.set_from_profile! profile
              Sketchup.active_model.selection.clear
              Sketchup.active_model.selection.add i
              VBO::ShapeForge.profile_dialog.refresh
            end
          }
        }
        Sketchup.active_model.commit_operation
        records, length = create_records
        dialog_height = [170 + (length + 4) * 25.4, 1100].min
        @manager.set_size 1000, dialog_height
        script = %Q{
          var h = [170 + (#{length} + 4) * 25.4, 1100]
          var height = Math.min(...h) - 60
          $("#grid").height(height);
          w2ui.grid.records = #{records.to_json};
          w2ui.grid.records.filter(function(c){
            return !isNaN(c.recid);
          }).forEach(function(c){
            w2ui.grid.expand(c.recid);
          });
          w2ui.grid.records.forEach(function(c){
            if (c.w2ui.children != []) {
              w2ui.grid.expand(c.recid);
            }
          });
          w2ui.grid.refresh();
        }
        @manager.execute_script script
      }

      @manager.add_action_callback("edit"){ |action, data|


      }

      @manager.add_action_callback("reload"){ |action, data|
        records, length = create_records
        if @manager
          dialog_height = [170 + (length + 4) * 25.4, 1100].min
          @manager.set_size 1000, dialog_height
          script = %Q{
            var h = [170 + (#{length} + 4) * 25.4, 1100]
            var height = Math.min(...h) - 60
            $("#grid").height(height);
            w2ui.grid.records = #{records.to_json};
            w2ui.grid.records.filter(function(c){
              return !isNaN(c.recid);
            }).forEach(function(c){
              w2ui.grid.expand(c.recid);
            });
            w2ui.grid.records.forEach(function(c){
              if (c.w2ui.children != []) {
                w2ui.grid.expand(c.recid);
              }
            });
            w2ui.grid.refresh();
          }
          @manager.execute_script script
          # self.handleReload
        end
      }
      @manager.add_action_callback("resize"){ |action, data|
        length = data
        dialog_height = [170 + (length + 4) * 25.4, 1100].min
        @manager.set_size 1000, dialog_height
        script = %Q{
          var h = [170 + (#{length} + 4) * 25.4, 1100]
          var height = Math.min(...h) - 60
          $("#grid").height(height);
          w2ui.grid.refresh();
        }
        @manager.execute_script script
      }
      @manager.add_action_callback("excel_grid"){ |action, items|
        columns = items[0].map{|c|[c['field'], c['caption']]}.to_h
        records = items[1]
        hash = []
        records.each{|r|
          hash << columns.keys.sort_by{|c| create_columns.map{|co| co[:caption]}.index(c)}.map{|c| [columns[c], r[c]]}.to_h
        }
        workbooks = {'Shapes' => hash}
        save_to_excel(File.basename(Sketchup.active_model.path, '.skp'),workbooks)
      }

      @manager.add_action_callback("select"){ |action, data|
        Sketchup.active_model.selection.clear
        data.each{|dat|
          pids = dat["pids"]
          pids = dat["w2ui"]["children"].map{|c| c["pids"]}.flatten if pids.nil?
          pids.map{|c| Sketchup.active_model.find_entity_by_persistent_id(c)}.each{|c| Sketchup.active_model.selection.add c.instances}
        }

      }
      @manager.show
      Sketchup.active_model.active_view.invalidate
    end
    def handleReload
      call_manager
      call_manager
    end
  end
end
