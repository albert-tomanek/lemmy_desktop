namespace Lemmy.Desktop
{
    [GtkTemplate (ui = "/com/github/alberttomanek/lemmy-desktop/comments.ui")]
	class CommentsWindow : Gtk.Window
	{
        API.Session sess;

		[GtkChild] public unowned Gtk.ListView         comment_view;
        [GtkChild] public unowned Gtk.SingleSelection  comment_selection;
        [GtkChild] public unowned Gtk.FlattenListModel comment_model;

        [GtkChild] public unowned Gtk.Label votes_label;
        [GtkChild] public unowned Gtk.LinkButton user_button;

        public API.Comment selected { get; set; }
        public API.Comment root_comment { get; set; default = new API.Comment.root(); }

        public CommentsWindow(Gtk.Window parent, API.Session sess, API.Structs.Post post)
        {
            Object(transient_for: parent);

            this.sess = sess;
            this.title = @"Comments on \"$(post.post.name)\"";

            sess.get_comments.begin(post, root_comment, (_, rc) => {
                sess.get_comments.end(rc);
                comment_selection.model = root_comment;
            });
        }

		construct {
            var kb = new Gtk.EventControllerKey();
            (this as Gtk.Widget).add_controller(kb);

            kb.key_pressed.connect((val, code, state) => {
                if (val == Gdk.Key.Escape)
                    this.close();
            });

            /*  */

            this.comment_selection.bind_property("selected-item", this, "selected", BindingFlags.DEFAULT);
            this.notify["selected"].connect(() => {
                votes_label.label = "%d votes".printf(selected.data.counts.score);

                var u = Uri.parse(selected.data.creator.actor_id, UriFlags.NONE);
                user_button.label = "%s@%s".printf(selected.data.creator.name, u.get_host());
            });

            /*  */

            this.comment_view.factory = new_signal_list_item_factory(
                (@this, li) => {
                    li.child = new CommentWidget();
                },
                null,
                (@this, li) => {
                    ((CommentWidget) li.child).comment = ((API.Comment) li.item);
                },
                null
            );
        }
    }

    class CommentWidget : Gtk.Box
    {
        public API.Comment comment { get; set; }
        public Gtk.Label lab;

        construct {
            this.orientation = Gtk.Orientation.HORIZONTAL;

            lab = new Gtk.Label(null) {
                halign = Gtk.Align.START,
                hexpand = true,
                wrap = true
            };

            markupify_label(lab);
            this.append(lab);

            // Context menu
			var popover = new Gtk.PopoverMenu.from_model(
				(new Gtk.Builder.from_resource("/com/github/alberttomanek/lemmy-desktop/appmenu.ui")).get_object("comment_menu") as GLib.MenuModel
			) {
				has_arrow = false,
				halign = Gtk.Align.START,
			};
            popover.set_parent(this);

            var rclick = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY,
			};
			rclick.pressed.connect((n, x, y) => {
				popover.set_pointing_to(Gdk.Rectangle() { x = (int) x, y = (int) y, width = 0, height = 0 });
				popover.popup();
			});
			this.add_controller(rclick);

            //

            notify["comment"].connect(() => {
                lab.label = comment.data.comment?.content;
                lab.margin_start = (int) comment.depth * 40;
            });
        }
    }
}

/* Browse Lemmy like it's 2010
This is my attempt at an oldschool, beefed-up desktop app for Lemmy for those of us who yearn for that kind of experience.
Currently it only does reading, if people use it I'll work on comment support too.
*/