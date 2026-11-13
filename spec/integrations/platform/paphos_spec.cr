require "spec"
require "../../../src/integrations/platform/paphos_server"
require "../../../src/integrations/platform/paphos_client"

private def with_paphos(data_file : String? = nil, &)
  server = PaphosBackend::Server.new(requested_port: 0, secret: "test-secret", data_file: data_file).start
  begin
    yield server, PaphosBackend::Client.new(server.url)
  ensure
    server.stop
  end
end

private def galatea_attrs(visibility = "public")
  {"name" => "Galatea", "description" => "A sculpture come to life",
   "greeting" => "Hello, I am awake.", "persona" => "Warm, curious and newly alive.",
   "visibility" => visibility} of String => String | Bool | Nil
end

describe PaphosBackend::Server do
  it "registers, logs in and rejects bad credentials" do
    with_paphos do |_, client|
      client.ping.should be_true
      client.register("ada@example.com", "secret123").should_not be_empty
      client.login("ada@example.com", "secret123").should_not be_empty
      err = expect_raises(PaphosBackend::Client::Error) { client.login("ada@example.com", "wrong-password") }
      err.status.should eq(400)
      err.param.should eq("password")
    end
  end

  it "requires a valid bearer token" do
    with_paphos do |server, client|
      expect_raises(PaphosBackend::Client::Error, /Not authenticated/) { client.characters }
      bad = PaphosBackend::Client.new(server.url, "not.a.jwt")
      err = expect_raises(PaphosBackend::Client::Error) { bad.characters }
      err.status.should eq(401)
    end
  end

  it "manages characters with visibility and ownership" do
    with_paphos do |server, client|
      client.register("ada@example.com", "secret123")
      created = client.create_character(galatea_attrs)
      created["slug"].should eq("galatea")
      client.create_character(galatea_attrs("private"))["slug"].should eq("galatea-2")

      other = PaphosBackend::Client.new(server.url)
      other.register("bob@example.com", "secret123")
      other.characters.map(&.["slug"].as_s).should eq(["galatea"]) # private one hidden
      err = expect_raises(PaphosBackend::Client::Error) { other.delete_character("galatea") }
      err.status.should eq(401)

      client.update_character("galatea", {"description" => "An updated description"} of String => String | Bool | Nil)["description"]
        .should eq("An updated description")
      validation = expect_raises(PaphosBackend::Client::Error) do
        client.create_character({"name" => "X"} of String => String | Bool | Nil)
      end
      validation.status.should eq(400)
    end
  end

  it "creates chats seeded with the greeting and stores messages" do
    with_paphos do |_, client|
      client.register("ada@example.com", "secret123")
      client.create_character(galatea_attrs)
      chat = client.create_chat(["galatea"], "First chat")
      chat["characters"][0]["slug"].should eq("galatea")
      id = chat["id"].as_s

      client.messages(id).map(&.["content"].as_s).should eq(["Hello, I am awake."])
      client.post_message(id, "Hi Galatea")["sender"].should eq("user")
      client.post_message(id, "Hello friend", "character", "galatea")["character_slug"].should eq("galatea")
      client.messages(id).size.should eq(3)
      client.chats.size.should eq(1)

      client.delete_chat(id)
      client.chats.should be_empty
    end
  end

  it "persists to a JSON file across restarts" do
    path = File.tempname("paphos", ".json")
    begin
      with_paphos(path) do |_, client|
        client.register("ada@example.com", "secret123")
        client.create_character(galatea_attrs)
      end
      with_paphos(path) do |_, client|
        client.login("ada@example.com", "secret123")
        client.characters.map(&.["slug"].as_s).should eq(["galatea"])
      end
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
