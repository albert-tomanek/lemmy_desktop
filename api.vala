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
        stdout.printf("%s\n", (string) response.get_data().copy());
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
        requires(list.item_type == typeof(Structs.Community))
        {
            yield fetch_all_paged(@"https://$(inst)/api/v3/community/list?type_=Subscribed", "$.communities[*]", typeof(Structs.Community), list);
        }

        public async void get_comments(Structs.Post post, Comment root) throws Error
        {
            // This is a list where comments are temporarily stored while the API page with their parents hasn't been received yet. Eventually, all comments from this list should get removed from this list and inserted somewhere into the tree under `root`.
            var comments_flat = new ListStore(typeof(Structs.Comment));

            yield fetch_all_paged(@"https://$(inst)/api/v3/comment/list?post_id=$(post.post.id)", "$.comments[*]", typeof(Structs.Comment), comments_flat, () => {
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

        internal async void fetch_all_paged(string url, string json_path, Type item_type, ListStore dest, SourceOnceFunc? new_page_cb = null) throws Error
        {
            //  stdout.printf("A %d %d\n", (int) list.get_n_items(), (int) (-1 < (int) list.get_n_items()));
            for (int old_length = -1, page = 1; old_length < (int) dest.get_n_items(); page++) // We stop iterating once the pages (ie. additions) have size 0.
            {
                old_length = (int) dest.get_n_items();

                yield this.fetch_page(url, json_path, item_type, dest, page);

                if (new_page_cb != null)
                    new_page_cb();
            }
        }

        internal async void fetch_page(string url, string json_path, Type item_type, ListStore dest, uint page) throws Error
        {
            var request = new Soup.Message ("GET", url + ("?" in url ? "&" : "?") + @"page=$(page)");
            var bytes = yield soup.send_and_read_async(request, 0, null);

            var nodes = Json.Path.query(json_path, Json.from_string((string) bytes.get_data())).get_array();
            nodes.foreach_element((arr, i, node) => {
                var c = Json.gobject_deserialize(item_type, node);
                dest.append(c);
            });
        }
    }

    class Comment : ListModel, Object
    {
        // Comment tree info
        weak Comment? parent = null;
        public bool is_root { get { return parent == null; } }

        ListStore            replies = new ListStore(typeof(Comment));
        Gtk.SortListModel    replies_sorted;
        Gtk.FlattenListModel flat;

        public Structs.Comment? data { get; construct; }
        public uint path_id { get; private set; }

        // Configurable props
        public enum Sort
        {
            TOP,
            NEW
        }

        public Sort sort { get; set; }
        public bool collapsed { get; set; default = false; }

        public Comment(Structs.Comment data)
        {
            Object(data: data);
        }

        public Comment.root()
        {
            Object(data: null);
        }

        construct {
            GLib.CompareDataFunc<Comment> cmp = (a, b) => this.sort_comments(a, b);
            replies_sorted = new Gtk.SortListModel(this.replies, new Gtk.CustomSorter(cmp));
            this.notify["sort"].connect(() => replies_sorted.sorter.changed(Gtk.SorterChange.DIFFERENT));

            flat = new Gtk.FlattenListModel(replies_sorted);
            flat.items_changed.connect(this.items_changed);

            if (this.data != null)
            {
                var path_parts = this.data.comment.path.split(".");
                this.path_id = uint.parse(path_parts[path_parts.length - 1]);
            }

            notify["collapsed"].connect(() => {
                if (!this.is_root)
                {
                    if (this.collapsed == true)
                        this.items_changed(1, flat.get_n_items(), 0);
                    else
                        this.items_changed(1, 0, flat.get_n_items());
                }
            });
        }

        public Object? get_item (uint idx) 
        {
            if (this.is_root)
                return flat.get_item(idx);  // The root comment is actually empty so just pass through the children
            else
                return (idx == 0) ? this : flat.get_item(idx - 1);
        }

        public Type get_item_type()
        {
            return flat.get_item_type();
        }

        public uint get_n_items()
        {
            int this_len = this.is_root ? 0 : 1;

            return (this.collapsed) ? this_len : this_len + flat.get_n_items();
        }

        //

        private int sort_comments(Comment a, Comment b)
        {
            switch (this.sort)
            {
                case Sort.TOP:
                default:
                    return (a.data.counts.score > b.data.counts.score) ? -1 : 1;
            }
        }

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
            this.bind_property("sort", repl, "sort", BindingFlags.DEFAULT);     // Sort setting should propagate down the whole tree.
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

    class SubmissionIter: GLib.ListModel, Object
    {
        // For https://lemmy.readme.io/reference/get_post-list

        API.Session sess;

        string url;
        string json_path;

        ListStore submissions;
        uint page = 1;

        public SubmissionIter.group(API.Session sess, string comm_inst, string comm)
        {
            this.sess = sess;
            this.url = @"https://$(sess.inst)/api/v3/post/list?community_name=$(comm)@$(comm_inst)";
            this.json_path = "$.posts[*]";
            this.submissions = new ListStore(typeof(Structs.Post));
        }

        public SubmissionIter.on_url(API.Session sess, string url, string json_path, Type type)
        {
            this.sess = sess;
            this.url = url;
            this.json_path = json_path;
            this.submissions = new ListStore(type);
        }

        public async uint get_more_posts()
        {
            var old_length = get_n_items();

            yield this.sess.fetch_page(this.url, this.json_path, this.submissions.get_item_type(), this.submissions, this.page++);

            this.items_changed(old_length, 0, get_n_items() - old_length);
            return get_n_items() - old_length;
        }

        public SubmissionIter exhaust()
        {
            exhaust_async.begin();

            return this;
        }

        private async void exhaust_async()
        {
            for (uint more = 1; more > 0;)
                more = yield get_more_posts();
        }

        // ListModel

        public Type get_item_type()
        {
            return submissions.get_item_type();
        }

        public uint get_n_items ()
        {
            return submissions.get_n_items();
        }

        public Object? get_item (uint i)
        {
            return submissions.get_item(i);
        }
    }

    // JSON objects

    public class Structs.UserSubmission : Object, Json.Serializable
    {
        public class Creator : Object, Json.Serializable
        {
            public string actor_id { get; set; }
            public string name { get; set; }
            public string? avatar { get; set; default = null; }
        }
        public Creator creator { get; set; }

        public class Counts : Object, Json.Serializable
        {
            public int score { get; set; }
            public int upvotes { get; set; }
            public int downvotes { get; set; }
        }
        public Counts counts { get; set; }
    }

    public class Structs.Post : Structs.UserSubmission, Json.Serializable
    {
        public class Data : Object, Json.Serializable   // https://stackoverflow.com/a/58461239/6130358
        {
            public int id { get; set; }
            public string name { get; set; }
            public string? url { get; set; default = null; }
            public string? body { get; set; default = null; }
            public bool locked { get; set; }
            public string ap_id { get; set; }
            public bool featured_community { get; set; }
    
            // Need parsing
            public string published { get; set; }
            public DateTime m_published { owned get { return new DateTime.from_iso8601(published, new TimeZone.utc()); } }  // Assume server time is UTC
        }
        public Data post { get; set; }
    }

    public class Structs.Comment : Structs.UserSubmission, Json.Serializable
    {
        public class CommentField : Object, Json.Serializable
        {
            public int id { get; set; }
            public string content { get; set; }
            public string published { get; set; }   // ISO date
            public DateTime m_published { owned get { return new DateTime.from_iso8601(published, new TimeZone.utc()); } }
            public bool   deleted { get; set; }
            public string path { get; set; }

            public string ap_id { get; set; }
        }
        public CommentField comment { get; set; }

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

    public class Structs.Community : Object, Json.Serializable
    {
        public string subscribed { get; set; }
        public bool   m_subscribed { get { return subscribed == "Subscribed"; } }
        public bool   blocked { get; set; }

        public class Data : Object, Json.Serializable
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
        public Data community { get; set; }

        public class Counts : Object, Json.Serializable
        {
            public int subscribers { get; set; }
            public int posts { get; set; }
        }
        public Counts counts { get; set; }
    }
}
