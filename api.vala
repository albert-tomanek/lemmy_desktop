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
        var? token = json_get("$.jwt", (string) response.get_data()).get_string();

        if (token != null)
            return token;
        else
            throw new APIError.LOGIN(json_get("$.error", (string) response.get_data()).get_string());
    }

    async bool check_token(string inst, string token) throws Error
    {
        var soup = new Soup.Session();
        
        var request = new Soup.Message ("GET", @"https://$inst/api/v3/user/validate_auth");
        request.request_headers.append("Authorization", "Bearer " + token);
        
        var response = yield soup.send_and_read_async(request, 0, null);
        bool? success = json_get("$.success", (string) response.get_data().copy()).get_boolean();

        if (success != null)
            return success;
        else
            return false;
            //  throw new APIError.LOGIN(json_get("$.error", (string) response.get_data()).get_string());
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
        }

        //  public static async Session? login_with_token(const Desktop.AccountInfo acc) throws Error
        //  {
        //  }

        //  public static async Session? login_with_token(string jwt) throws Error  // Returns null if token expored. Then user must login manually.
        //  {
        //      var sess = new Session() { inst = inst, uname = uname };
        //      sess.soup = new Soup.Session();
            
        //      var msg = new Soup.Message ("POST", @"https://$(inst)/api/v3/user/validate_auth");
        //      var body = @"{\"username_or_email\": \"$uname\", \"password\": \"$passwd\"}";
        //      msg.set_request_body_from_bytes("application/json", new Bytes (body.data));
            
        //      var response = yield sess.soup.send_and_read_async(msg, 0, null);
            
        //      sess.token = json_get("$.jwt", (string) response.get_data()).get_string();
        //      if (sess.token == null)
        //          throw new APIError.LOGIN(json_get("$.error", (string) response.get_data()).get_string());

        //      return sess;
        //  }

        public async void get_subscribed(ListStore list) throws Error
        requires(list.item_type == typeof(Handles.Community))
        {
            //  stdout.printf("A %d %d\n", (int) list.get_n_items(), (int) (-1 < (int) list.get_n_items()));
            for (int old_length = -1, page = 1; old_length < (int) list.get_n_items(); page++) // We stop iterating once the pages (ie. additions) have size 0.
            {
                old_length = (int) list.get_n_items();

                var request = new Soup.Message ("GET", @"https://$(inst)/api/v3/community/list?type_=Subscribed&page=$(page)");
                request.request_headers.append("Authorization", "Bearer " + this.token);
                var bytes = yield soup.send_and_read_async(request, 0, null);
                
                var nodes = Json.Path.query("$.communities..community", Json.from_string((string) bytes.get_data())).get_array();
                nodes.foreach_element((arr, i, node) => {
                    var c = (Handles.Community) Json.gobject_deserialize(typeof(Handles.Community), node);
                    list.append(c);
                });
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
            msg.request_headers.append("Authorization", "Bearer " + sess.token);
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
        public string name { get; set; }
        public string? url { get; set; default = null; }
        public string? body { get; set; default = null; }
        public bool locked { get; set; }

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

        public string instance {    // IIRC getter return values are always unowned
            owned get {
                return Uri.parse(actor_id, UriFlags.NONE).get_host().dup();
            }
        }
    }
}