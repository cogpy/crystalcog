require "../spec_helper"
require "../../src/integrations/ipfs_integration"

describe CrystalCog::Integrations do
  describe CrystalCog::Integrations::IPFSConfig do
    it "creates config with default values" do
      config = CrystalCog::Integrations::IPFSConfig.new
      config.api_host.should eq "localhost"
      config.api_port.should eq 5001
      config.gateway_host.should eq "localhost"
      config.gateway_port.should eq 8080
      config.pin_by_default.should be_true
    end

    it "generates correct API URL" do
      config = CrystalCog::Integrations::IPFSConfig.new(api_host: "ipfs.example.com")
      config.api_url.should eq "http://ipfs.example.com:5001/api/v0"
    end

    it "generates correct gateway URL" do
      config = CrystalCog::Integrations::IPFSConfig.new(gateway_port: 8081)
      config.gateway_url.should eq "http://localhost:8081"
    end
  end

  describe CrystalCog::Integrations::IPFSCid do
    it "creates CID" do
      cid = CrystalCog::Integrations::IPFSCid.new("QmTest123")
      cid.hash.should eq "QmTest123"
      cid.version.should eq 1
      cid.to_s.should eq "QmTest123"
    end

    it "generates gateway URL" do
      config = CrystalCog::Integrations::IPFSConfig.new
      cid = CrystalCog::Integrations::IPFSCid.new("QmTest123")
      cid.gateway_url(config).should eq "http://localhost:8080/ipfs/QmTest123"
    end

    it "generates IPFS path" do
      cid = CrystalCog::Integrations::IPFSCid.new("QmTest123")
      cid.ipfs_path.should eq "/ipfs/QmTest123"
    end

    it "compares CIDs" do
      cid1 = CrystalCog::Integrations::IPFSCid.new("QmTest123")
      cid2 = CrystalCog::Integrations::IPFSCid.new("QmTest123")
      cid3 = CrystalCog::Integrations::IPFSCid.new("QmOther456")

      (cid1 == cid2).should be_true
      (cid1 == cid3).should be_false
    end
  end

  describe CrystalCog::Integrations::IPFSObject do
    it "creates IPFS object" do
      cid = CrystalCog::Integrations::IPFSCid.new("QmTest")
      obj = CrystalCog::Integrations::IPFSObject.new(
        cid: cid,
        size: 1024_i64,
        type: "file"
      )

      obj.cid.hash.should eq "QmTest"
      obj.size.should eq 1024
      obj.type.should eq "file"
    end
  end

  describe CrystalCog::Integrations::IPFSLink do
    it "creates IPFS link" do
      link = CrystalCog::Integrations::IPFSLink.new(
        name: "child",
        hash: "QmChild",
        size: 512_i64
      )

      link.name.should eq "child"
      link.hash.should eq "QmChild"
      link.size.should eq 512
      link.cid.hash.should eq "QmChild"
    end
  end

  describe CrystalCog::Integrations::IPFSPeer do
    it "creates peer info" do
      peer = CrystalCog::Integrations::IPFSPeer.new(
        id: "QmPeer123",
        addresses: ["/ip4/127.0.0.1/tcp/4001"],
        agent_version: "go-ipfs/0.12.0"
      )

      peer.id.should eq "QmPeer123"
      peer.addresses.size.should eq 1
      peer.agent_version.should eq "go-ipfs/0.12.0"
    end
  end

  describe CrystalCog::Integrations::IPFSPinInfo do
    it "creates pin info" do
      cid = CrystalCog::Integrations::IPFSCid.new("QmTest")
      pin = CrystalCog::Integrations::IPFSPinInfo.new(
        cid: cid,
        pin_type: CrystalCog::Integrations::IPFSPinType::Recursive
      )

      pin.cid.hash.should eq "QmTest"
      pin.pin_type.should eq CrystalCog::Integrations::IPFSPinType::Recursive
    end
  end

  describe CrystalCog::Integrations::IPFSDagNode do
    it "creates DAG node" do
      node = CrystalCog::Integrations::IPFSDagNode.new
      node.links.should be_empty
    end

    it "adds links" do
      node = CrystalCog::Integrations::IPFSDagNode.new
      cid = CrystalCog::Integrations::IPFSCid.new("QmChild")
      node.add_link("child", cid, 100_i64)

      node.links.size.should eq 1
      node.links.first.name.should eq "child"
      node.links.first.hash.should eq "QmChild"
    end

    it "converts to JSON" do
      node = CrystalCog::Integrations::IPFSDagNode.new(
        data: JSON.parse({"key" => "value"}.to_json)
      )

      json = node.to_json
      json.should contain "Data"
      json.should contain "Links"
    end
  end

  describe CrystalCog::Integrations::IPFSAtom do
    it "creates IPFS atom" do
      atom = CrystalCog::Integrations::IPFSAtom.new(
        id: "atom-1",
        atom_type: "ConceptNode",
        name: "Dog"
      )

      atom.id.should eq "atom-1"
      atom.atom_type.should eq "ConceptNode"
      atom.name.should eq "Dog"
      atom.truth_value_strength.should eq 1.0
    end

    it "converts to JSON" do
      atom = CrystalCog::Integrations::IPFSAtom.new(
        id: "atom-1",
        name: "Cat"
      )

      json = atom.to_json
      json.as_h["id"].should eq JSON::Any.new("atom-1")
      json.as_h["name"].should eq JSON::Any.new("Cat")
    end

    it "parses from JSON" do
      json = JSON.parse({
        "id"         => "atom-2",
        "atomType"   => "PredicateNode",
        "name"       => "likes",
        "tvStrength" => 0.8,
      }.to_json)

      atom = CrystalCog::Integrations::IPFSAtom.from_json(json)
      atom.should_not be_nil
      atom.not_nil!.id.should eq "atom-2"
      atom.not_nil!.atom_type.should eq "PredicateNode"
      atom.not_nil!.truth_value_strength.should eq 0.8
    end

    it "computes content hash" do
      atom1 = CrystalCog::Integrations::IPFSAtom.new(
        atom_type: "ConceptNode",
        name: "Dog"
      )
      atom2 = CrystalCog::Integrations::IPFSAtom.new(
        atom_type: "ConceptNode",
        name: "Dog"
      )

      atom1.compute_content_hash.should eq atom2.compute_content_hash
    end
  end

  describe CrystalCog::Integrations::IPFSStorageStats do
    it "creates storage stats" do
      cid = CrystalCog::Integrations::IPFSCid.new("QmRoot")
      stats = CrystalCog::Integrations::IPFSStorageStats.new(
        repo_size: 1000000_i64,
        storage_max: 10000000_i64,
        num_objects: 500_i64,
        root_cid: cid,
        atomspace_name: "test"
      )

      stats.repo_size.should eq 1000000
      stats.storage_max.should eq 10000000
      stats.usage_percent.should eq 10.0
    end

    it "handles zero storage max" do
      stats = CrystalCog::Integrations::IPFSStorageStats.new
      stats.usage_percent.should eq 0.0
    end
  end
end
