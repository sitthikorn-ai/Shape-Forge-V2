Sketchup.require File.join(File.dirname(__FILE__), 'dialog')
Sketchup.require File.join(File.dirname(__FILE__), 'canvas')
module VBO::ShapeForge
  class Dialog1

    def js_functions_toolbars
      %Q{
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
          if (id === 'member_toolbar') {
            // Center horizontally at its current vertical position
            $(`#${id}`).css({
              position:'absolute',
              display: 'block',
              left: '50%',
              transform: 'translateX(-50%)',
              width: 'auto',
              'background-color': 'white'
            });
            // Help center internal toolbar structure
            $(`#${id} .w2ui-toolbar`).css({
              margin: '0 auto'
            });
          } else {
            $(`#${id}`).css({
              position:'absolute',
              display: 'block',
              width: `100%`,
              left: 0,
              'background-color': 'white',
            });
          }
          if (id === 'settings') {
            // Hide spacer, break, and trailing right cell by their td IDs
            w2ui[id].items.forEach(function(item) {
              if (item.type === 'spacer' || item.type === 'break') {
                $(`#tb_${id}_item_` + item.id).hide();
              }
            });
            $(`#tb_${id}_right`).hide();
            // Distribute buttons evenly using flex on the main table row
            $(`#${id} .w2ui-scroll-wrapper > table > tbody > tr`).css({
              'display': 'flex',
              'justify-content': 'space-evenly',
              'width': '100%',
              'align-items': 'center'
            });
          }
        }
      }
    end

    def toolbar_settings
      options = Options.new
      %Q{{
        name : 'settings',
        items: [

          {
            type: 'check',
            id: 'click_edit',
            tooltip: 'Enable click-edit',
            text: '',
            icon: 'fa fa-code-fork fa-rotate-90' ,

            checked: #{options.click_edit}
          },
          {
            type: 'check',
            id: 'scale_rebuild',
            tooltip: 'Enable Scaling Rebuild',
            text: '',
            icon: 'fa fa-object-group' ,
            checked: #{options.scale_rebuild}
          },
          {
            type: 'check',
            id: 'delete_edges',
            tooltip: 'Enable Delete Edges After Apply',
            text: '',
            icon: 'fa fa-share-alt fa-rotate-270 ',
            checked: #{options.delete_edges}
          },
          {
            type: 'break'
          },
          {
            type: 'check',
            id: 'magic',
            tooltip: 'Magic Wand',
            text: '',
            icon: 'fa fa-magic' ,
            checked: false
          },
          {
            type: 'spacer'
          },
          {
            type: 'button',
            id: 'profile_connect',
            tooltip: 'Shape Connect',
            text: '',
            img: 'icon-profile-connect',
          },
          {
            type: 'button',
            id: 'home',
            tooltip: 'In Model',
            text: '',
            icon: 'fa fa-home',
            items: [

            ]
          },

          {
            type: 'button',
            id: 'load',
            tooltip: 'Load SKP',
            text: '',
            icon: 'fa fa-folder-open-o'
          },
          {
            type: 'button',
            id: 'save',
            tooltip: 'Save Shape',
            disabled: true,
            text: '',
            icon: 'fa fa-floppy-o'
          },

          {
            type: 'button',
            id: 'help',
            tooltip: 'Help',
            text: '',
            icon: 'fa fa-book'
          },

        ],
        onClick: function (event) {
          event.onComplete = function() {
            switch (event.target) {
              case 'click_edit':
              case 'scale_rebuild':
              case 'delete_edges':
                sketchup.action(event.target,w2ui.settings.get(event.target).checked);
                break;
              case 'magic' :
                sketchup.action('magic',w2ui.settings.get('magic').checked);
              break;
              case 'save':
                sketchup.action('save');
                break;
              case 'load' :
                sketchup.action('load');
                break;
              case 'home' :
                sketchup.action('report');
                break;
              case 'profile_connect' :
                sketchup.action('profile_connect');
                break;
              default:
              sketchup.action(event.target);
            }
          }
        }
      }}
    end

    def toolbar_profile
      options = Options.new
      %Q{{
        name : 'profile_toolbar',
        items: [
          {
            type: 'check',
            id: 'pinned',
            text: '',
            icon: 'fa fa-thumb-tack fa-rotate-270' ,
            tooltip: 'Pin This Shape',
            checked: #{options.pinned}
          },
          {
            type: 'break'
          },
          {
            type: 'check',
            id: 'draw_profile',
            text: '',
            icon: 'fa fa-pencil fa-rotate-270' ,
            tooltip: 'Draw This Shape',
            checked: #{options.pinned}
          },
          {
            type: 'button',
            id: 'append',
            tooltip: 'Append Shape',
            text: '',
            disabled: #{!options.pinned},
            icon: 'fa fa-puzzle-piece fa-rotate-270'
          },

          {
            type: 'button',
            id: 'apply',
            tooltip: 'Apply Shape',
            disabled: #{!options.pinned},
            text: '',
            img: 'w2ui-icon icon-roller fa-rotate-270'
          },

          {
            type: 'button',
            id: 'apply_flask',
            tooltip: 'Apply Shape (Break)',
            disabled: #{!options.pinned},
            text: '',
            icon: 'w2ui-icon icon-flask fa-rotate-270'
          },

          {
            type: 'check',
            id: 'select_apply',
            tooltip: 'Selective Apply',
            disabled: #{!options.pinned},
            text: '',
            icon: "fa fa-check-square-o fa-rotate-270"
          },
                    {
            type: 'break'
          },
          {
            type: 'check',
            id: 'extrude_mode',
            tooltip: 'Normal Mode',
            text: '',
            icon: "fa fa-codepen fa-rotate-270"
          },
          {
            type: 'button',
            id: 'smooth_angle',
            tooltip: 'Smooth Angle',
            text: '',
            icon: "w2ui-icon smooth fa-rotate-270"
          },
          {
            type: 'break'
          },
          {
            type: 'button',
            id: 'stamp_profile',
            tooltip: 'Stamp Shape',
            text: '',
            icon: "fa fa-sign-in"
          },
          {
            type: 'button',
            id: 'project_profile',
            tooltip: 'Re-Project Shape',
            text: '',
            icon: 'fa fa-pencil-square-o fa-rotate-270'
          },

        ],
        onClick: function (event) {
          event.onComplete = function() {
            switch (event.target) {

              case 'pinned' :
                sketchup.action('pinned', w2ui.profile_toolbar.get('pinned').checked);
                break;
              case 'select_apply' :
                sketchup.action('select_apply', w2ui.profile_toolbar.get('select_apply').checked);
                break;
              case 'extrude_mode':
                sketchup.action('extrude_mode', w2ui.profile_toolbar.get('extrude_mode').checked);
                break;
              default:
                sketchup.action(event.target);
                break;
            }
          }
        }
      }}
    end

    def toolbar_member
      get_members
      options = Options.new
      %Q{{
        name : 'member_toolbar',
        items: [
          {
            type: 'button',
            id: 'object_to_forge',
            text: '',
            icon: 'fa fa-exchange fa-rotate-270',
            tooltip: 'Object to Shape Forge'
          },
          {
            type: 'break'
          },
          {
            type: 'check',
            id: 'select_member',
            tooltip: 'Select Active Elements',
            disabled: #{self.temp_profile.nil?},
            text: '',
            img: "icon-filter",
          },
          {
            type: 'check',
            id: 'trim_plane',
            tooltip: 'Trim/Extend to Plane',

            text: '',
            img: "icon-trim-plane"
          },
          /*
          {
            type: 'check',
            id: 'trim_solid',
            tooltip: 'Trim To Solid',

            text: '',
            img: "icon-trim-solid"
          },
          */
          {
            type: 'button',
            id: 'reverse',
            tooltip: 'Reverse Path',

            text: '',
            img: 'icon-reverse'
          },
          {
            type: 'button',
            id: 'close',
            tooltip: 'Close / Open Path',

            text: '',
            img: 'icon-open-close'
          },

          /*{
            type: 'menu',
            id: 'path_functions',
            tooltip: 'Path Functions',
            disabled: #{!@members || @members.empty?},
            text: '',

            img: "icon-path-edit",
            items: [
              {
                id: 'reverse', text: 'Reverse Path', img: 'icon-reverse',
                disabled: #{!@members || @members.empty?},
              },
              {
                id: 'close', text: 'Open / Close Path', img: 'icon-reverse',
                disabled: #{!@members || @members.empty?},
              },
              {text:'---'},
              {
                id: 'join-normal', text: 'Join Elements - Normal', img:"icon-join-normal",
                disabled: #{!@members || @members.length != 2},
              },
              {
                id: 'join-miter', text: 'Join Elements - Miter', img:"icon-split-miter",
                disabled: #{!@members || @members.length != 2},
              },
              {
                id: 'join-butt', text: 'Join Elements - Butt', img:"icon-split-butt",
                disabled: #{!@members || @members.length != 2},
              },

            ]
          },*/

          {
            type: 'menu',
            id: 'junction_style',
            tooltip: 'Junction Style',
            text: '',
            img: 'icon-split-#{@temp_profile&.junction_style == 'miter_joint' ? 'miter' : @temp_profile&.junction_style == 'butt_joint' ? 'butt' : @temp_profile&.junction_style == 'normal' ? 'normal' : 'continuous'}',
            items: [
              {
                id: 'continuous', text: 'Continuous', img:"icon-split-continuous"
              },
              {
                id: 'normal', text: 'Normal Split', img:"icon-split-normal"
              },
              {
                id: 'miter_joint', text: 'Miter Joints', img:"icon-split-miter"
              },
              {
                id: 'butt_joint', text: 'Butt Joints', img:"icon-split-butt"
              }
            ]
          },
          {
            type: 'menu',
            id: 'split',
            tooltip: 'Split Elements',
            text: '',
            img: 'icon-split-miter',
            disabled: #{!@members || @members.empty?},
            items: [
              {
                id: 'normal', text: 'Normal', img:"icon-split-normal"
              },
              //{text:'---'},
              {
                id: 'miter', text: 'Miter Joints',img:"icon-split-miter"
              },
              //{text:'---'},
              {
                id: 'butt', text: 'Butt Joints',img:"icon-split-butt"
              },
            ]
          },
          {
            type: 'menu',
            id: 'project_member',
            tooltip: "Re-Projected",
            disabled: #{!@members || @members.empty?},
            text: '',
            img: "icon-spacing",
            items: [
              {
                id: 'to_model_axes', text: "To Model's Axes"
              },
              {
                id: 'by_member', text: "By First Edge of Path"
              },
            ]
          },
        ],
        onClick: function (event) {
          event.onComplete = function() {
            switch (event.target) {
              case 'pinned' :
              case 'select_member' :
              case 'trim_plane' :
              case 'trim_solid' :
                sketchup.action(event.target, w2ui.member_toolbar.get(event.target).checked);
                break;
              case 'path_functions':
              case 'split':
              case 'junction_style':
              case 'project_member':
                break;
              default:
                sketchup.action(event.target);
            }
          }
        }
      }}
    end

    def form_selective
      %Q{{
        name: 'selective',
        fields: [
          {
            field: 'fullname',
            type: 'checkbox',
            html: {
              span: 4,
              column:0,
              caption: 'Shape/Name<br>/Width/Height',
            }
          },
          {
            field: 'mirror',
            type: 'checkbox',
            html: {
              span: 3,
              column: 1,
              caption: 'Mirror',
            }
          },
          {
            field: 'rotation',
            type: 'checkbox',
            html: {
              span: 4,
              column:2,
              caption: 'Rotation',
            }
          },
          {
            field: 'placement_point',
            type: 'checkbox',
            html: {
              span: 4,
              column: 0,
              caption: 'Placement<br>Point',
            }
          },
          {
            field: 'x_offset',
            type: 'checkbox',
            html: {
              span: 3,
              column:1,
              caption: 'X Offset',

            }
          },
          {
            field: 'y_offset',
            type: 'checkbox',
            html: {
              span: 4,
              column: 2,
              caption: 'Y Offset',
            }
          },
          {
            field: 'material_name',
            type: 'checkbox',
            html: {
              span: 4,
              column:0,
              caption: 'Material',

            }
          },
          {
            field: 'layer_name',
            type: 'checkbox',
            html: {
              span: 3,
              column: 1,
              caption: '#{Sketchup.version.to_i.ceil > 19 ? 'Tag' : 'Layer'}',
            }
          },
          {
            field: 'extrude_mode',
            type: 'checkbox',
            html: {
              span: 4,
              column: 2,
              caption: 'Extrude Mode'
            }
          },
        ],

      }}
    end

  end
end
