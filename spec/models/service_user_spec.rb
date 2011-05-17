require 'spec_helper'

describe ServiceUser do

  describe '#finder' do
    before do
      @user = alice
      @post = @user.post(:status_message, :text => "hello", :to =>@user.aspects.first.id)
      @service = Services::Facebook.new(:access_token => "yeah")
      @user.services << @service

      @user2 = Factory.create(:user_with_aspect)
      @user2_fb_id = '820651'
      @user2_fb_name = 'Maxwell Salzberg'
      @user2_fb_photo_url = 'http://cdn.fn.com/pic1.jpg'
      @user2_service = Services::Facebook.new(:uid => @user2_fb_id, :access_token => "yo")
      @user2.services << @user2_service
      @fb_list_hash =  <<JSON
      {
        "data": [
          {
            "name": "#{@user2_fb_name}",
            "id": "#{@user2_fb_id}",
            "picture": ""
          },
          {
            "name": "Person to Invite",
            "id": "abc123",
            "picture": "http://cdn.fn.com/pic1.jpg"
          }
        ]
      }
JSON
      @web_mock = mock()
      @web_mock.stub!(:body).and_return(@fb_list_hash)
      RestClient.stub!(:get).and_return(@web_mock)
    end

    context 'lifecycle callbacks' do
      before do
        @su = ServiceUser.create(:service_id => @service.id, :uid => @user2_fb_id, :name => @user2_fb_name,
                            :photo_url => @user2_fb_photo_url)
      end
      it 'contains a name' do
        @su.name.should == @user2_fb_name
      end
      it 'contains a photo url' do
        @su.photo_url.should == @user2_fb_photo_url
      end
      it 'contains a FB id' do
        @su.uid.should == @user2_fb_id
      end
      it 'contains a diaspora person object' do
        @su.person.should == @user2.person
      end
      it 'queries for the correct service type' do
        Services::Facebook.should_receive(:where).with(hash_including({:type => "Services::Facebook"})).and_return([])
        @su.send(:attach_local_models)
      end
      it 'does not include the person if the search is disabled' do
        p = @user2.person.profile
        p.searchable = false
        p.save
        @su.save
        @su.person.should be_nil
      end

      context "request" do
        before do
          @request = Request.diaspora_initialize(:from => @user2.person, :to => @user.person, :into => @user2.aspects.first)
          Postzord::Receiver.new(@user, :object => @request, :person => @user2.person).receive_object
          Request.count.should == 1
        end
        it 'contains a request object if one has been sent' do
          @su.save
          @su.request.should == @request
        end
      end

      it 'contains a contact object if connected' do
        connect_users(@user, @user.aspects.first, @user2, @user2.aspects.first)
        @su.save
        @su.contact.should == @user.reload.contact_for(@user2.person)
      end

      context 'already invited' do
        before do
          @user2.invitation_service = 'facebook'
          @user2.invitation_identifier = @user2_fb_id
          @user2.save!
        end
        it 'contains an invitation if invited' do
          @inv = Invitation.create(:sender => @user, :recipient => @user2, :aspect => @user.aspects.first)
          @su.save
          @su.invitation_id.should == @inv.id
        end
        it 'does not find the user with a wrong identifier' do
          @user2.invitation_identifier = 'dsaofhnadsoifnsdanf'
          @user2.save

          @inv = Invitation.create(:sender => @user, :recipient => @user2, :aspect => @user.aspects.first)
          @su.save
          @su.invitation_id.should be_nil
        end
      end
    end
  end
end

describe FakeServiceUser do
  describe '.initialize' do
    before do
      @data = [182, "820651", "Maxwell Salzberg", "http://cdn.fn.com/pic1.jpg", 299, 1610, nil, nil, nil, DateTime.parse("Tue May 17 00:31:44 UTC 2011"), DateTime.parse("Tue May 17 00:31:44 UTC 2011")]
      @fake = FakeServiceUser.new(@data)
    end
    it 'takes a mysql row and sets the attr names to their values' do
      @fake[:id].should == @data[0]
      @fake[:uid].should == @data[1]
      @fake[:name].should == @data[2]
      @fake[:photo_url].should == @data[3]
      @fake[:service_id].should == @data[4]
      @fake[:person_id].should == @data[5]
      @fake[:contact_id].should == @data[6]
      @fake[:request_id].should == @data[7]
      @fake[:invitation_id].should == @data[8]
      @fake[:created_at].should == @data[9]
      @fake[:updated_at].should == @data[10]
    end

    it 'has reader methods' do
      @fake.photo_url.should == @data[3]
      @fake.person_id.should == @data[5]
    end

    it 'has association methods' do
      person = mock
      Person.should_receive(:find).with(@data[5]).and_return person
      @fake.person.should == person
    end

    it 'does not error on an association with no id' do
      @fake[:person_id] = nil
      lambda{ @fake.person }.should_not raise_error
    end
  end
end
