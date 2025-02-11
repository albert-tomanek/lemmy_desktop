namespace LemmyDesktop
{
    class GroupIter: GLib.ListModel, Object
    {
        public string instance { get; construct; }
        public string comm { get; construct; }

        GenericArray<PostHandle> posts = new GenericArray<PostHandle>();
        string? next_page = null;

        Soup.Session sess;

        public GroupIter(string instance, string comm)
        {
            Object(instance: instance, comm: comm);
        }

        construct {
            this.sess = new Soup.Session();
        }

        public async void get_more_posts()
        {
            var _old_length = get_n_items();

            var bytes = yield sess.send_and_read_async(     // https://lemmy.readme.io/reference/get_post-list
                new Soup.Message ("GET", @"https://$(instance)/api/v3/post/list?community_name=$(comm)" + (next_page != null ? "&page_cursor=" + next_page : "")),
                0,
                null
            );

            //
            
            var pa = new Json.Parser();
            pa.load_from_data((string) bytes.get_data(), bytes.length);
            var r  = new Json.Reader(pa.get_root());

            r.read_member("next_page");
            this.next_page = r.get_string_value();
            r.end_member();

            r.read_member("posts");
            var n_items = r.count_elements();
            for (int i = 0; i < n_items; i++)
            {
                posts.add(
                    Json.gobject_deserialize(
                        typeof(PostHandle),
                        Json.Path.query("$.posts[%d].post".printf(i), pa.get_root())
                            .get_array().get_element(0)
                    ) as PostHandle
                );
            }
            r.end_member();
            
            this.items_changed(_old_length, 0, n_items);
        }

        // ListModel

        public Type get_item_type()
        {
            return typeof(PostHandle);
        }

        public uint get_n_items ()
        {
            return this.posts.length;
        }

        public Object? get_item (uint i)
        {
            return (i < get_n_items()) ? this.posts[i] : null;
        }
    }

    public class PostHandle : Object, Json.Serializable   // https://stackoverflow.com/a/58461239/6130358
    {
        public string name { get; set; }
        public bool locked { get; set; }

        // Need parsing
        public string published { get; set; }

        //  public Post get_post()
    }
}