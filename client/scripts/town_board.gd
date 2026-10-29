extends RefCounted
## Native board reader and draft composer; publishes only after server acknowledgement.
var host_ref: WeakRef
var host: RefCounted:
 get:return host_ref.get_ref() as RefCounted
var tabs: HBoxContainer
var read_tab: Button
var post_tab: Button
var publish_button: Button
var tab: int=0
var draft_subject: String=""
var draft_body: String=""
var board_key: String=""
var selected_post: int=0
var posts: Array=[]
var post_heading: String=""

func build(owner: RefCounted) -> void:
 host_ref=weakref(owner);tabs=HBoxContainer.new();tabs.position=Vector2(28,76);tabs.size=Vector2(884,52);tabs.add_theme_constant_override("separation",10);host.card.add_child(tabs)
 read_tab=host.game._button(tabs,"Read",Vector2.ZERO,Vector2(170,50),func() -> void:choose(0))
 post_tab=host.game._button(tabs,"Post",Vector2.ZERO,Vector2(170,50),func() -> void:choose(1))
 for button: Button in [read_tab,post_tab]:button.custom_minimum_size=Vector2(170,50);button.toggle_mode=true
 publish_button=host.game._button(host.card,"Publish post",Vector2(28,572),Vector2(884,50),publish)
 publish_button.hide();tabs.hide()

func opened(location: Dictionary) -> void:
 save_draft()
 var key: String=str(host.game.world.get("id",0))+":"+str(location)
 if key!=board_key:draft_subject="";draft_body=""
 board_key=key;tab=0;selected_post=0;posts=[];post_heading=""

func save_draft() -> void:
 if host.kind!="board" or tab!=1:return
 if host.fields.has("subject") and is_instance_valid(host.fields.subject):draft_subject=str(host.fields.subject.text)
 if host.fields.has("body") and is_instance_valid(host.fields.body):draft_body=str(host.fields.body.text)

func choose(value: int) -> void:
 if host.busy:return
 save_draft();host.blur();tab=value;host.render();host.scroll.scroll_vertical=0

func receive(reply: Dictionary,operation: String) -> void:
 if reply.has("posts"):
  posts=(reply.posts as Array).duplicate(true)
  if operation=="feature_action":draft_subject="";draft_body="";tab=0
 if reply.has("body"):
  tab=0
  for post: Dictionary in posts:
   if int(post.id)==int(reply.get("post_id",0)):post_heading=str(post.subject)+"\n"+str(post.author)

func render() -> void:
 tabs.show();publish_button.visible=tab==1;read_tab.set_pressed_no_signal(tab==0);post_tab.set_pressed_no_signal(tab==1)
 if tab==1:
  host.field("subject","Subject · up to 64 characters");host.field("body","Message · up to 256 characters",false,true)
  host.fields.subject.text=draft_subject;host.fields.body.text=draft_body
  host.fields.body.custom_minimum_size.y=170
  var count: Label=host.label("%d / 256"%draft_body.length());count.add_theme_font_size_override("font_size",16)
  host.fields.body.text_changed.connect(func() -> void:count.text="%d / 256"%str(host.fields.body.text).length())
  return
 if host.state.has("body"):
  var title: Label=host.label(post_heading);title.add_theme_color_override("font_color",host.game.GOLD)
  var message: Label=host.label(str(host.state.body));message.text_direction=Control.TEXT_DIRECTION_AUTO
  host.button("Back to posts",func() -> void:host.state.erase("body");host.render())
  return
 host.label("Town messages · %d posts"%posts.size())
 if posts.is_empty():host.label("No messages yet. Use Post to leave the first one.");return
 var list: ItemList=ItemList.new();list.custom_minimum_size.y=230;list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_font_size_override("font_size",21);host.content.add_child(list);host.fields.list=list
 for post: Dictionary in posts:
  var index: int=list.add_item(str(post.subject)+"  ·  "+str(post.author));list.set_item_metadata(index,int(post.id));list.set_item_tooltip(index,str(post.subject)+" — "+str(post.author))
  if int(post.id)==selected_post:list.select(index)
 list.item_selected.connect(func(index: int) -> void:selected_post=int(list.get_item_metadata(index)))
 list.item_activated.connect(func(_index: int) -> void:read_selected())
 host.button("Read selected post",read_selected)
 if int((host.game.online.player.get("stats",{}) as Dictionary).get("admin",0))>0:
  host.button("Remove selected post",func() -> void:
   if selected_post<=0:host.status.text="Select a message first.";return
   host.ask("Remove this post?",func() -> void:host.action("remove",selected_post))
  )

func read_selected() -> void:
 if selected_post<=0:host.status.text="Select a message first.";return
 host.action("read",selected_post)

func publish() -> void:
 save_draft()
 if draft_subject.strip_edges().is_empty() or draft_body.strip_edges().is_empty():host.status.text="Enter a subject and a message.";return
 if draft_body.length()>256:host.status.text="Keep the message within 256 characters.";return
 host.ask("Publish this message on the town board?",func() -> void:host.action("post",0,draft_subject,draft_body))
