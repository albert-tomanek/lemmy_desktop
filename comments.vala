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
        public MarkdownLabel lab = new MarkdownLabel();

        construct {
            this.orientation = Gtk.Orientation.HORIZONTAL;
            this.margin_start = 4;
            this.margin_end   = 4;

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
                lab.text = comment.data.comment?.content;
                lab.margin_start = ((int) comment.depth - 1) * 40;  // The root comment doesn't get displayed so everything is actually 1 level shallower than it reports.
            });
        }
    }

    class MarkdownLabel : Gtk.Box
    {
        public string text { get; set; }
        public bool selectable { get; set; default = false; }

        construct {
            this.orientation = Gtk.Orientation.VERTICAL;
            this.spacing = 8;

            notify["text"].connect(() => {
                this.remove_children();

                var R_IMAGE = new Regex("\\n?!\\[(.*?)\\]\\((\\w+:\\/\\/\\S+?)\\)\\n?");
                var R_IMAGE_NC = new Regex("\\n?!\\[(?:.*?)\\]\\((?:\\w+:\\/\\/\\S+?)\\)\\n?");    // Non-capturing version. Otherwise it'd get included in the .split() result (per docs)
                string[] text_parts = R_IMAGE_NC.split(this.text);

                MatchInfo image_match;
                R_IMAGE.match(this.text, 0, out image_match);

                foreach (var text_part in text_parts)
                {
                    var lab = new Gtk.Label(text_part) {
                        halign = Gtk.Align.START,
                        hexpand = true,
                        wrap = true,
                        selectable = this.selectable
                    };        
                    markupify_label(lab);
                    this.append(lab);

                    if (image_match.matches())
                    {
                        var pic = new Gtk.Picture() {
                            height_request = 150,
                            alternative_text = image_match.fetch(1)
                        };
                        set_picture_to_url.begin(pic, image_match.fetch(2));
                        this.append(pic);

                        // Image viewing
                        var click = new Gtk.GestureClick() {
                            button = Gdk.BUTTON_PRIMARY,
                        };
                        click.pressed.connect((n, x, y) => {
                            FileIOStream stream;
                            var file = File.new_tmp("embed-XXXXXX.png", out stream);
                            stream.get_output_stream().write_bytes_async.begin(
                                (pic.paintable as Gdk.Texture).save_to_png_bytes(), Priority.DEFAULT, null,
                                (_, rc) => {
                                    stream.get_output_stream().write_bytes_async.end(rc);
                                    AppInfo.launch_default_for_uri_async.begin(file.get_uri(), null);
                                }
                            );
                        });
                        pic.add_controller(click);            

                        image_match.next();
                    }
                }
            });
        }

        void remove_children()
        {
            while (this.get_last_child() != null)
                this.remove(this.get_last_child());
        }
    }

    void markupify_label(Gtk.Label lab)
    {
        lab.use_markup = true;

        lab.set_data<bool>("ignore-text-change", false);
        lab.notify["label"].connect(() => {
            if (lab.get_data<bool>("ignore-text-change"))
            {
                // `::notify` triggered by this callback
                lab.set_data<bool>("ignore-text-change", false);
            }
            else
            {
                lab.set_data<bool>("ignore-text-change", true);

                string text = lab.label;

                // https://docs.gtk.org/Pango/pango_markup.html
                // https://docs.gtk.org/gtk4/class.Label.html#markup-styled-text
                // https://join-lemmy.org/docs/users/02-media.html

                //  string URL = "http(s)?:\\/\\/?[\\w.-]+(?:\\.[\\w\\.-]+)+[\\w\\-\\._~:/?#[\\]@!\\$&'\\(\\)\\*\\+,;=.]+";
                string URL = "\\w+:\\/\\/\\S+";// + "(?=\\))";
                string CMTY = "![\\w_]+@[\\w\\.]+";

                // Cmty links
                text = regex_replace(text, "\\[("+CMTY+")]\\(\\S+\\)", "<a href=\"lemmy://\\1\">\\1</a>");
                text = regex_replace(text, "(\\s)("+CMTY+")", "\\1<a href=\"lemmy://\\2\">\\2</a>");  // Raw urls in the text that arent []() links (and aren't already whithin a tag, that's the first bit)

                // URLs
                text = regex_replace(text, "\\[(.*?)]\\(("+URL+")\\)", "<a href=\"\\2\">\\1</a>");
                text = regex_replace(text, "(\\s)("+URL+")", "\\1<a href=\"\\2\">\\2</a>");  // Raw urls in the text that arent []() links (and aren't already whithin a tag, that's the first bit)

                text = regex_replace(text, "\\*\\*(.*?)\\*\\*", "<b>\\1</b>");
                text = regex_replace(text, "\\*(.*?)\\*", "<i>\\1</i>");
                text = regex_replace(text, "(?:\s)_(\\w.*?\\w)_(?:\s)", "<i>\\1</i>");
                text = regex_replace(text, "~~(\\w.*?\\w)~~", "<s>\\1</s>");
                text = regex_replace(text, "`(.*?)`", "<tt>\\1</tt>");

                text = regex_replace(text, "(?<=^|\\n)# (.*?)(?=\\n)", "<big><b>\\1</b></big>");

                lab.label = text;

                // Setup handling of lemmy links
                lab.activate_link.connect(uri => {
                    if (uri.has_prefix("lemmy://"))
                        stdout.printf("Opening %s\n", uri[8:]);
                    else
                        AppInfo.launch_default_for_uri_async.begin(uri, null);

                    return true;
                });
            }
        });

        lab.notify_property("label");
    }
}