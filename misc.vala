unowned Gtk.ExpressionWatch deep_bind(Object tgt_obj, string tgt_prop, Object src_obj, ...)
{
	// Equivalent:
	//
	//  var post_text = new Gtk.PropertyExpression(typeof(API.Handles.Post),
	//  	new Gtk.PropertyExpression(typeof(PostView), null, "post"),
	//  "body");
	//  post_text.bind(body_label, "label", this);
	//
	//  deep_bind(
	//  	body_label, "label",
	//  	this, typeof(PostView), "post", typeof(API.Handles.Post), "body"
	//  );

	string[] props = {};
	Type[]   types = {};

	// 1. extract the va_args
	for (var l = va_list(); true;)
	{
		Type type = l.arg();
		if (type == 0) break;
		types += type;

		string prop = l.arg();
		props += prop;
	}

	// 2. Construct the nested expression
	Gtk.Expression? exp = null;
	for (int i = 0; i < props.length; i++)
	{
		exp = new Gtk.PropertyExpression(types[i], exp, props[i]);
	}

	if (exp != null)
		return exp.bind(tgt_obj, tgt_prop, src_obj);
	else
		return null;
}


delegate void SignalListItemFactoryCallback(Gtk.SignalListItemFactory @this, Gtk.ListItem li);

Gtk.SignalListItemFactory new_signal_list_item_factory(
    SignalListItemFactoryCallback? setup,
    SignalListItemFactoryCallback? teardown,
    SignalListItemFactoryCallback? bind,
    SignalListItemFactoryCallback? unbind
)
{
    var f = new Gtk.SignalListItemFactory();

    if (setup    != null) f.setup.connect((t, li) => setup(f, (Gtk.ListItem) li));      // FIXME: We get passed Objects, not ListItems so this cast might be ignoring some aspect of reaity
    if (teardown != null) f.teardown.connect((t, li) => teardown(f, (Gtk.ListItem) li));
    if (bind     != null) f.bind.connect((t, li) => bind(f, (Gtk.ListItem) li));
    if (unbind   != null) f.unbind.connect((t, li) => unbind(f, (Gtk.ListItem) li));

    return f;
}


void errbox (Gtk.Window parent, string title, string text)
{
	var d2 = new Gtk.MessageDialog(parent, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, null) {
		text = title,
		secondary_text = text,
	};
	d2.response.connect(_ => d2.close());
	d2.show();
}


string regex_replace(string text, string patt, string repl)
{
    return (new Regex(patt)).replace(text, text.length, 0, repl);
}


async void set_image_to_url(Gtk.Image img, string url)
{
    var bytes = yield (new Soup.Session()).send_and_read_async(new Soup.Message ("GET", url), 0, null);
    img.gicon = new GLib.BytesIcon(bytes);
}

async void set_picture_to_url(Gtk.Picture pic, string url)
{
    var bytes = yield (new Soup.Session()).send_and_read_async(new Soup.Message ("GET", url), 0, null);
    pic.paintable = Gdk.Texture.from_bytes(bytes);
}


public Gtk.Widget get_li_cell(Gtk.ListItem li)
{
	return li.child.parent;
}

public Gtk.Widget get_li_row(Gtk.ListItem li)
{
	return li.child.parent.parent;
}


public string age_humanized(DateTime d)
{
	TimeSpan diff = (new DateTime.now()).difference(d);

	if (diff < TimeSpan.SECOND)
		return "now";
	else if (diff < TimeSpan.MINUTE)
		return @"$(diff / TimeSpan.SECOND) seconds";
	else if (diff < TimeSpan.HOUR)
		return @"$(diff / TimeSpan.MINUTE) minutes";
	else if (diff < TimeSpan.DAY)
		return @"$(diff / TimeSpan.HOUR) hours";
	else if (diff < (TimeSpan.DAY * 7))
		return @"$(diff / TimeSpan.DAY) days";
	else if (diff < (TimeSpan.DAY * 28))
		return @"$(diff / (TimeSpan.DAY * 7)) weeks";
	else if (diff < (TimeSpan.DAY * 365))
		return @"$(diff / (TimeSpan.DAY * 28)) months";
	else
		return @"$(diff / (TimeSpan.DAY * 365)) years";
}