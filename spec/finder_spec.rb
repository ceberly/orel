require 'helper'

describe Orel::Finder do

  let(:user) {
    UsersAndThings::User.create! :first_name => "John", :last_name => "Smith", :age => 33
  }

  let(:thing) {
    UsersAndThings::Thing.create! :name => "Box", UsersAndThings::User => user
  }

  subject { Orel::Finder.new(klass, klass.table, klass.get_heading) }

  describe "in general" do
    let(:klass) { UsersAndThings::User }

    describe "#find_by_key" do
      it "raises an error if the key does not exist" do
        expect { subject.find_by_key(:other, "John") }.to raise_error(ArgumentError, "Key :other does not exist")
      end
    end

    describe "#find_all" do
      before do
        @user1 = UsersAndThings::User.create! :first_name => "John", :last_name => "Smith", :age => 33
        @user2 = UsersAndThings::User.create! :first_name => "Mary", :last_name => "Smith", :age => 33
        @user3 = UsersAndThings::User.create! :first_name => "Mary", :last_name => "Jones", :age => 33
      end
      it "returns an empty array if nothing is found" do
        UsersAndThings::User.find_all(:first_name => "Bob").should == []
      end
      it "returns matching records" do
        records = UsersAndThings::User.find_all(:last_name => "Smith")
        records.size.should == 2
        records.should =~ [@user1, @user2]
      end
      specify "the resulting records are valid and persisted" do
        records = UsersAndThings::User.find_all(:first_name => "John")
        records.size.should == 1
        records.first.should be_persisted
        records.first.should be_valid
      end

    end
  end

  describe "a class with a composite natural key" do
    let(:klass) { UsersAndThings::User }
    before { user }

    describe "#find_by_key" do
      context "with hash args" do
        specify "it returns a persisted object" do
          object = subject.find_by_key(:primary, :first_name => "John", :last_name => "Smith")
          object.should == user
          object.should be_persisted
          object.should be_valid
        end
        it "returns nil if nothing matches" do
          object = subject.find_by_key(:primary, :first_name => "John", :last_name => "Doe")
          object.should be_nil
        end
        specify "it raises an ArgumentError if the hash args don't match the key" do
          expect { subject.find_by_key(:primary, :first_name => "John") }.to raise_error(ArgumentError)
        end
        specify "it raises an ArgumentError if extra args are given" do
          expect { subject.find_by_key(:primary, { :first_name => "John" }, nil) }.to raise_error(ArgumentError)
        end
      end
      context "with ordered args" do
        specify "it returns a persisted object" do
          object = subject.find_by_key(:primary, "John", "Smith")
          object.should == user
          object.should be_persisted
          object.should be_valid
        end
        it "returns nil if nothing matches" do
          object = subject.find_by_key(:primary, "John", "Doe")
          object.should be_nil
        end
        specify "it raises an ArgumentError if the hash args don't match the key" do
          expect { subject.find_by_key(:primary, "John") }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe "a class with a surrogate key" do
    let(:klass) { UsersAndThings::Thing }
    before { thing }

    describe "#find_by_key" do
      context "with hash args" do
        specify "it returns a persisted object" do
          object = subject.find_by_key(:primary, :id => thing.id)
          object.should == thing
          object.should be_persisted
          object.should be_valid
        end
        specify "it returns nil of nothing matches" do
          object = subject.find_by_key(:primary, :id => 0)
          object.should be_nil
        end
        specify "it raises an ArgumentError if the hash args don't match the key" do
          expect {subject.find_by_key(:primary, :foo => thing.id) }.to raise_error(ArgumentError)
        end
      end
    end
  end
end
