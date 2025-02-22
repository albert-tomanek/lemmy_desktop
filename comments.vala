namespace Lemmy.Desktop
{
    [GtkTemplate (ui = "/com/github/alberttomanek/lemmy-desktop/comments.ui")]
	class CommentsWindow : Gtk.Window
	{
        API.Session sess;

		[GtkChild] public unowned Gtk.ListView         comment_view;
        [GtkChild] public unowned Gtk.SingleSelection  comment_selection;
        [GtkChild] public unowned Gtk.FlattenListModel comment_model;

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

            this.comment_view.factory = new_signal_list_item_factory(
                (@this, li) => {
                    li.child = new Gtk.Label(null) {
                        halign = Gtk.Align.START,
                        hexpand = true,
                        wrap = true
                    };
                },
                null,
                (@this, li) => {
                    // ((Gtk.Label) li.child).label = li.position.to_string() + ((API.Comment) li.item).data.comment?.content;
                    ((Gtk.Label) li.child).label = ((API.Comment) li.item).data.comment?.content ?? li.position.to_string();
                    ((Gtk.Label) li.child).margin_start = (int) ((API.Comment) li.item).depth * 20;
                    //  stdout.printf("\t%u %p\n", li.position, ((API.Comment) li.item));
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