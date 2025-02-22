Json.Node? json_get(string path, string data) throws Error
{
    Json.Array res = Json.Path.query(path, Json.from_string(data)).get_array();

    return res.get_length() > 0 ? res.get_element(0) : null;
}

errordomain Lemmy.APIError {
    LOGIN
}

namespace Lemmy.API
{
    async string login(string inst, string uname, string passwd) throws Error
    {
        var soup = new Soup.Session();

        var msg = new Soup.Message ("POST", @"https://$inst/api/v3/user/login");
        var body = @"{\"username_or_email\": \"$uname\", \"password\": \"$passwd\"}";
        msg.set_request_body_from_bytes("application/json", new Bytes (body.data));

        var response = yield soup.send_and_read_async(msg, 0, null);
        var? token = json_get("$.jwt", (string) response.get_data().copy()).get_string();

        if (token != null)
            return token;
        else
            throw new APIError.LOGIN(json_get("$.error", (string) response.get_data().copy()).get_string());
    }

    async bool check_token(string inst, string token) throws Error
    {
        // https://lemmy.readme.io/reference/validateauth

        var soup = new Soup.Session();

        var request = new Soup.Message ("GET", @"https://$inst/api/v3/user/validate_auth");
        request.request_headers.append("Authorization", "Bearer " + token);

        var response = yield soup.send_and_read_async(request, 0, null);
        var response_text = (string) response.get_data().copy();
        response_text = response_text[:response_text.last_index_of_char('}')+1];
        stdout.printf("%s\n", response_text);

        bool? success = json_get("$.success", response_text).get_boolean();

        if (success != null)
            return success;
        else
            return false;
            //  throw new APIError.LOGIN(json_get("$.error", (string) response.get_data().copy()).get_string());
    }

    class Session
    {
        internal Soup.Session soup;

        public string inst { get; private set; }
        public string uname { get; private set; }

        public string token { get; private set; }

        public Session(string inst, string uname, string token)
        {
            this.inst = inst;
            this.uname = uname;
            this.token = token;

            this.soup = new Soup.Session();

            var cookiejar = new Soup.CookieJar();
            cookiejar.add_cookie(new Soup.Cookie("jwt", token, inst, "/", -1));
            this.soup.add_feature(cookiejar);
        }

        public async void get_subscribed(ListStore list) throws Error
        requires(list.item_type == typeof(Handles.Community))
        {
            yield fetch_all_paged(@"https://$(inst)/api/v3/community/list?type_=Subscribed", "$.communities..community", typeof(Handles.Community), list);
        }

        public async void get_comments(Handles.Post post, Comment root) throws Error
        {
            // This is a list where comments are temporarily stored while the API page with their parents hasn't been received yet. Eventually, all comments from this list should get removed from this list and inserted somewhere into the tree under `root`.
            var comments_flat = new ListStore(typeof(Structs.Comment));

            yield fetch_all_paged(@"https://$(inst)/api/v3/comment/list?post_id=$(post.id)", "$.comments[*]", typeof(Structs.Comment), comments_flat, () => {
            });

            do {
                for (uint i = 0; i < comments_flat.n_items; i++)
                {
                    Structs.Comment unsorted = comments_flat.get_item(i) as Structs.Comment;
    
                    Comment? parent = root.get_comment_at_path(unsorted.parent_path);
                    if (parent != null)
                    {
                        parent.add_reply(new Comment(unsorted));
    
                        // Remove from temporary list
                        comments_flat.remove(i);
                        i--;
                    }
                }
                stdout.printf("Unsorted: %d\n", (int) comments_flat.get_n_items());
            } while (comments_flat.get_n_items() > 0);
        }

        private async void fetch_all_paged(string url, string json_path, Type item_type, ListStore dest, SourceOnceFunc? new_page_cb = null) throws Error
        {
            //  stdout.printf("A %d %d\n", (int) list.get_n_items(), (int) (-1 < (int) list.get_n_items()));
            for (int old_length = -1, page = 1; old_length < (int) dest.get_n_items(); page++) // We stop iterating once the pages (ie. additions) have size 0.
            {
                old_length = (int) dest.get_n_items();

                var request = new Soup.Message ("GET", url + ("?" in url ? "&" : "?") + @"page=$(page)");
                var bytes = yield soup.send_and_read_async(request, 0, null);

                var nodes = Json.Path.query(json_path, Json.from_string((string) bytes.get_data())).get_array();
                nodes.foreach_element((arr, i, node) => {
                    var c = Json.gobject_deserialize(item_type, node);
                    dest.append(c);
                });

                if (new_page_cb != null)
                    new_page_cb();
            }
        }
    }

    class Comment : ListModel, Object
    {
        weak Comment? parent = null;

        ListStore replies = new ListStore(typeof(Comment));
        Gtk.FlattenListModel flat;

        public Structs.Comment? data { get; construct; }
        public uint path_id { get; private set; }

        public Comment(Structs.Comment data)
        {
            Object(data: data);
        }

        public Comment.root()
        {
            Object(data: null);
        }

        construct {
            flat = new Gtk.FlattenListModel(replies);
            flat.items_changed.connect(this.items_changed);

            if (this.data != null)
            {
                var path_parts = this.data.comment.path.split(".");
                this.path_id = uint.parse(path_parts[path_parts.length - 1]);
            }
        }

        public Object? get_item (uint idx) 
        {
            return (idx == 0) ? this : flat.get_item(idx - 1);
        }

        public Type get_item_type()
        {
            return flat.get_item_type();
        }

        public uint get_n_items()
        {
            return flat.get_n_items() + 1;
        }

        //

        public Comment? get_comment_at_path(uint[] path)
        {
            if (path.length == 0) return this;

            for (uint i = 0; i < this.replies.n_items; i++)
            {
                Comment child = this.replies.get_item(i) as Comment;

                if (child.path_id == path[0])
                    return child.get_comment_at_path(path[1:]);
            }

            return null;
        }

        public void add_reply(Comment repl)
        {
            this.replies.append(repl);
            repl.parent = this;
        }

        public uint depth {
            get {
                uint n = 0;

                for (Comment? cur = this; cur.parent != null; cur = cur.parent)
                    n++;
                
                return n;
            }
        }
    }

    class GroupIter: GLib.ListModel, Object
    {
        public string inst;
        public string comm;

        API.Session sess;

        GenericArray<Handles.Post> posts = new GenericArray<Handles.Post>();
        string? next_page = null;

        public GroupIter(API.Session sess, string inst, string comm)
        {
            this.sess = sess;
            this.inst = inst;
            this.comm = comm;
        }

        public async int get_more_posts()
        {
            var _old_length = get_n_items();

            var msg = new Soup.Message ("GET", @"https://$(inst)/api/v3/post/list?community_name=$(comm)" + (next_page != null ? "&page_cursor=" + next_page : ""));
            var bytes = yield sess.soup.send_and_read_async(msg, 0, null);

            //

            var pa = new Json.Parser();
            stdout.printf((string) bytes.get_data());
            pa.load_from_data((string) bytes.get_data(), bytes.length);
            var r  = new Json.Reader(pa.get_root());

            r.read_member("next_page");
            this.next_page = r.get_string_value();
            r.end_member();

            r.read_member("posts");
            var n_items = r.count_elements();
            for (int i = 0; i < n_items; i++)
            {
                Handles.Post post = Json.gobject_deserialize(
                    typeof(Handles.Post),
                    Json.Path.query("$.posts[%d].post".printf(i), pa.get_root())
                        .get_array().get_element(0)
                ) as Handles.Post;

                post.creator = Json.gobject_deserialize(
                    typeof(Handles.User),
                    Json.Path.query("$.posts[%d].creator".printf(i), pa.get_root())
                        .get_array().get_element(0)
                ) as Handles.User;

                posts.add(post);
            }
            r.end_member();

            this.items_changed(_old_length, 0, n_items);
            return n_items;
        }

        // ListModel

        public Type get_item_type()
        {
            return typeof(Handles.Post);
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

    class Post
    {
        public Post(Session sess)
        {

        }
    }

    // JSON objects

    public class Handles.Post : Object, Json.Serializable   // https://stackoverflow.com/a/58461239/6130358
    {
        public int id { get; set; }
        public string name { get; set; }
        public string? url { get; set; default = null; }
        public string? body { get; set; default = null; }
        public bool locked { get; set; }
        public string ap_id { get; set; }
        public bool featured_community { get; set; }

        public Handles.User creator;

        // Need parsing
        public string published { get; set; }

        //  public Post get_post(Session sess)
    }

    public class Handles.User : Object, Json.Serializable
    {
        public string name { get; set; }
    }

    public class Handles.Community : Object, Json.Serializable
    {
        public int id { get; set; }
        public string name { get; set; }
        public string title { get; set; }
        public string? description { get; set; default = null; }
        public string actor_id { get; set; }    // The link to the community in the HTML client
        public bool nsfw { get; set; }
        public string? icon { get; set; default = null; }

        public string instance {
            owned get {
                return Uri.parse(actor_id, UriFlags.NONE).get_host().dup();
            }
        }
    }

    public class Structs.Comment : Object, Json.Serializable
    {
        public class Comment : Object, Json.Serializable
        {
            public int id { get; set; }
            public string content { get; set; }
            public string published { get; set; }   // ISO date
            public bool   deleted { get; set; }
            public string path { get; set; }

            public string ap_id { get; set; }
        }

        public Comment comment { get; set; }

        //  public class Counts : Object, Json.Serializable
        //  {
        //      public int id { get; set; }
        //  }

        public uint[] parent_path {
            owned get {
                string[] parts = this.comment.path.split(".");

                uint[] i_parts = {};
                foreach (var p in parts)
                    i_parts += uint.parse(p);
                
                if (i_parts.length <= 2)
                    return {};
                else
                    return i_parts[1:i_parts.length - 1];
            }
        }
    }
}
