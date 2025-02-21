namespace Lemmy.Desktop
{
    [GtkTemplate (ui = "/com/github/alberttomanek/lemmy-desktop/comments.ui")]
	class CommentsWindow : Gtk.Window
	{
		[GtkChild] public unowned Gtk.ListView         comment_view;
        [GtkChild] public unowned Gtk.SingleSelection  comment_selection;
        [GtkChild] public unowned Gtk.FlattenListModel comment_model;

        public CommentsWindow(Gtk.Window parent, API.Session sess, API.Handles.Post post)
        {
            Object(transient_for: parent);

            this.title = @"Comments on \"$(post.name)\"";
        }

		construct {
            var kb = new Gtk.EventControllerKey();
            (this as Gtk.Widget).add_controller(kb);

            kb.key_pressed.connect((val, code, state) => {
                if (val == Gdk.Key.Escape)
                    this.close();
            });
        }
    }
}

/* Browse Lemmy like it's 2010
This is my attempt at an oldschool, beefed-up desktop app for Lemmy for those of us who yearn for that kind of experience.
Currently it only does reading, if people use it I'll work on comment support too.
*/