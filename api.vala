class LemmyDesktop.GroupIter: Object
{
    public string instance { get; construct; }
    public string comm { get; construct; }

    Soup.Session sess;

    public GroupIter(string instance, string comm)
    {
        Object(instance: instance, comm: comm);
    }

    construct {
        this.sess = new Soup.Session();
    }

    public async void get_posts()
    {
        var bytes = yield sess.send_and_read_async(
            new Soup.Message ("GET", @"https://$(instance)/api/v3/post/list?community_name=$(comm)"),
            0,
            null
        );

        //

        var posts = new GenericArray<Post>();
        
        var pa = new Json.Parser();
        pa.load_from_data((string) bytes.get_data(), bytes.length);
        var r  = new Json.Reader(pa.get_root());

        r.read_member("next_page");
        var next_page = r.get_string_value();
        r.end_member();

        r.read_member("posts");
        for (int i = 0; i < r.count_elements(); i++)
        {
            posts.add(
                Json.gobject_deserialize(
                    typeof(Post),
                    Json.Path.query("$.posts[%d].post".printf(i), pa.get_root())
                        .get_array().get_element(0)
                ) as Post
            );
        }
        r.end_member();
        
        posts.foreach(p => { stdout.printf(p.name + "\n"); });
    }

    //

    public class Post : Object, Json.Serializable   // https://stackoverflow.com/a/58461239/6130358
    {
        public string name { get; set; }
    }
}