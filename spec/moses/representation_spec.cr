require "spec"
require "../../src/moses/moses_framework"

describe MOSES::Representation do
  describe "representation types" do
    it "defines Tree representation" do
      MOSES::Tree.should be_truthy
    end

    it "defines Node representation" do
      MOSES::Node.should be_truthy
    end

    it "creates tree representation" do
      tree = MOSES::Tree.new
      tree.should_not be_nil
    end

    it "creates node representation" do
      node = MOSES::Node.new("x")
      node.should_not be_nil
      node.value.should eq("x")
    end
  end

  describe "tree operations" do
    it "adds nodes to tree" do
      tree = MOSES::Tree.new
      node = MOSES::Node.new("x")

      tree.add_node(node)
      tree.nodes.size.should eq(1)
      tree.nodes.first.should eq(node)
    end

    it "builds tree structure" do
      tree = MOSES::Tree.new
      root = MOSES::Node.new("root")
      child1 = MOSES::Node.new("child1")
      child2 = MOSES::Node.new("child2")

      tree.add_node(root)
      tree.add_child(root, child1)
      tree.add_child(root, child2)

      tree.children(root).size.should eq(2)
    end
  end

  describe "representation conversion" do
    it "converts tree to program" do
      tree = MOSES::Tree.new
      node = MOSES::Node.new("x")
      tree.add_node(node)

      program = tree.to_program
      program.should be_a(MOSES::Program)
    end
  end
end
