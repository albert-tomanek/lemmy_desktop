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

        public CommentsWindow(Gtk.Window parent, API.Session sess, API.Handles.Post post)
        {
            Object(transient_for: parent);

            this.sess = sess;
            this.title = @"Comments on \"$(post.name)\"";

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
                    var lab = new Gtk.Label(null) {
                        halign = Gtk.Align.START,
                        hexpand = true,
                        wrap = true
                    };
                    markupify_label(lab);
                    li.child = lab;
                },
                null,
                (@this, li) => {
                    ((Gtk.Label) li.child).label = ((API.Comment) li.item).data.comment?.content;
                    ((Gtk.Label) li.child).margin_start = (int) ((API.Comment) li.item).depth * 40;
                },
                null
            );
        }
    }
}

/* Browse Lemmy like it's 2010
This is my attempt at an oldschool, beefed-up desktop app for Lemmy for those of us who yearn for that kind of experience.
Currently it only does reading, if people use it I'll work on comment support too.
*/