require 'tempfile'

# rubocop:disable Layout/TrailingWhitespace
#
# Rational:  Needed for heredoc when testing HighLine output
describe ManageIQ::ApplianceConsole::UI::DatabaseAdmin, :with_ui do
  subject { described_class.new(input, output) }
  let(:signal_error) { ManageIQ::ApplianceConsole::MiqSignalError }

  describe "#initialize" do
    it "defaults @backup_type, @task, @task_params, @delete_agree, and @uri" do
      miq_dba = described_class.new
      expect(miq_dba.backup_type).to  eq(nil)
      expect(miq_dba.task).to         eq(nil)
      expect(miq_dba.task_params).to  eq([])
      expect(miq_dba.delete_agree).to eq(nil)
      expect(miq_dba.uri).to          eq(nil)
    end
  end

  describe "#run" do
    it "asks for file location, asks to delete backup, runs restore" do
      expect(subject).to receive(:say).with("Restore Database From Backup\n\n")
      expect(subject).to receive(:ask_file_location)
      expect(subject).to receive(:clear_screen)
      expect(subject).to receive(:say).with("Restore Database From Backup\n\n")
      expect(subject).to receive(:ask_to_delete_backup_after_restore)
      expect(subject).to receive(:confirm_and_execute)

      subject.run
    end
  end

  describe "#ask_file_location" do
    it "displays the menu" do
      expect(subject).to receive(:ask_local_file_options).once
      say ""
      subject.ask_file_location
      expect_output <<-PROMPT.strip_heredoc.chomp + " "
        Restore Database File

        1) Local file
        2) Network File System (NFS)
        3) Samba (SMB)
        4) Cancel

        Choose the restore database file: |1|
      PROMPT
    end

    it "defaults to local file" do
      expect(subject).to receive(:ask_local_file_options).once
      say ""
      subject.ask_file_location
      expect(subject.backup_type).to eq(described_class::LOCAL_FILE)
    end

    it "calls #ask_local_file_options when choosen" do
      expect(subject).to receive(:ask_local_file_options).once
      say "1"
      subject.ask_file_location
      expect(subject.backup_type).to eq(described_class::LOCAL_FILE)
    end

    it "calls #ask_nfs_file_options when choosen" do
      expect(subject).to receive(:ask_nfs_file_options).once
      say "2"
      subject.ask_file_location
      expect(subject.backup_type).to eq(described_class::NFS_FILE)
    end

    it "calls #ask_smb_file_options when choosen" do
      expect(subject).to receive(:ask_smb_file_options).once
      say "3"
      subject.ask_file_location
      expect(subject.backup_type).to eq(described_class::SMB_FILE)
    end

    it "cancels when CANCEL option is choosen" do
      say "4"
      expect { subject.ask_file_location }.to raise_error signal_error
    end
  end

  describe "#ask_local_file_options" do
    let(:file)      { Tempfile.new("foo.backup").tap(&:close) }
    let(:prmpt)     { "location of the local restore file" }
    let(:default)   { described_class::DB_RESTORE_FILE }
    let(:errmsg)    { "file that exists" }

    context "with no filename given" do
      before do
        # stub validator for default answer, since it probably doesn't exist on
        # the machine running these tests.
        stub_const("#{described_class.name}::LOCAL_FILE_VALIDATOR", ->(_) { true })

        say ""
        subject.ask_local_file_options
      end

      it "sets @uri to the default filename" do
        expect(subject.uri).to eq(default)
      end
    end

    context "with a valid filename given" do
      before do
        say file.path.to_s
        subject.ask_local_file_options
      end

      it "sets @uri to point to the local file" do
        expect(subject.uri).to eq(file.path)
      end

      it "sets @task to point to 'evm:db:restore:local'" do
        expect(subject.task).to eq("evm:db:restore:local")
      end

      it "sets @task_params to point to the local file" do
        expect(subject.task_params).to eq(["--", {:local_file => file.path}])
      end
    end

    context "with an invalid filename given" do
      let(:bad_filename) { "#{file.path}.bad_mmkay" }

      before do
        say [bad_filename, file.path.to_s]
        subject.ask_local_file_options
      end

      it "reprompts the user and then properly sets the options" do
        error = "Please provide #{errmsg}"
        expect_heard ["Enter the #{prmpt}: ", error, prompt]

        expect(subject.uri).to         eq(file.path)
        expect(subject.task).to        eq("evm:db:restore:local")
        expect(subject.task_params).to eq(["--", {:local_file => file.path}])
      end
    end
  end

  describe "#ask_nfs_file_options" do
    let(:example_uri) { subject.sample_url('nfs') }
    let(:prmpt)       { "location of the remote backup file\nExample: #{example_uri}" }
    let(:errmsg)      { "a valid URI" }

    context "with a valid uri given" do
      before do
        say example_uri
        subject.ask_nfs_file_options
      end

      it "sets @uri to point to the nfs file" do
        expect(subject.uri).to eq(example_uri)
      end

      it "sets @task to point to 'evm:db:restore:remote'" do
        expect(subject.task).to eq("evm:db:restore:remote")
      end

      it "sets @task_params to point to the nfs file" do
        expect(subject.task_params).to eq(["--", {:uri => example_uri}])
      end
    end

    context "with an invalid uri given" do
      let(:bad_uri) { "file://host.mydomain.com/path/to/file" }

      before do
        say [bad_uri, example_uri]
        subject.ask_nfs_file_options
      end

      it "reprompts the user and then properly sets the options" do
        error = "Please provide #{errmsg}"
        expect_heard ["Enter the #{prmpt}: ", error, prompt]

        expect(subject.uri).to         eq(example_uri)
        expect(subject.task).to        eq("evm:db:restore:remote")
        expect(subject.task_params).to eq(["--", {:uri => example_uri}])
      end
    end
  end

  describe "#ask_smb_file_options" do
    let(:example_uri) { subject.sample_url('smb') }
    let(:user)        { 'example.com/admin' }
    let(:pass)        { 'supersecret' }
    let(:uri_prompt)  { "Enter the location of the remote backup file\nExample: #{example_uri}" }
    let(:user_prompt) { "Enter the username with access to this file.\nExample: 'mydomain.com/user'" }
    let(:pass_prompt) { "Enter the password for #{user}" }
    let(:errmsg)      { "a valid URI" }

    let(:expected_task_params) do
      [
        "--",
        {
          :uri          => example_uri,
          :uri_username => user,
          :uri_password => pass
        }
      ]
    end

    context "with a valid uri, username, and password given" do
      before do
        say [example_uri, user, pass]
        subject.ask_smb_file_options
      end

      it "sets @uri to point to the smb file" do
        expect(subject.uri).to eq(example_uri)
      end

      it "sets @task to point to 'evm:db:restore:local'" do
        expect(subject.task).to eq("evm:db:restore:remote")
      end

      it "sets @task_params to point to the smb file, username, and password" do
        expect(subject.task_params).to eq(expected_task_params)
      end
    end

    context "with a invalid uri given" do
      let(:bad_uri) { "nfs://host.mydomain.com/path/to/file" }

      before do
        say [bad_uri, example_uri, user, pass]
        subject.ask_smb_file_options
      end

      it "reprompts the user and then properly sets the options" do
        error = "Please provide #{errmsg}"

        expect_readline_question_asked uri_prompt
        expect_readline_question_asked user_prompt
        expect_heard [
          uri_prompt,
          error,
          prompt,
          "#{pass_prompt}: ***********\n"
        ]

        expect(subject.uri).to         eq(example_uri)
        expect(subject.task).to        eq("evm:db:restore:remote")
        expect(subject.task_params).to eq(expected_task_params)
      end
    end
  end

  describe "#ask_to_delete_backup_after_restore" do
    context "when @backup_type is LOCAL_FILE" do
      let(:uri) { described_class::DB_RESTORE_FILE }

      before do
        subject.instance_variable_set(:@uri, uri)
        subject.instance_variable_set(:@backup_type, described_class::LOCAL_FILE)
      end

      it "sets @delete_agree if the user agrees" do
        say "y"
        subject.ask_to_delete_backup_after_restore
        expect_output <<-PROMPT.strip_heredoc.chomp + " "
          The local database restore file is located at: '#{uri}'.
          Should this file be deleted after completing the restore? (Y/N):
        PROMPT
      end

      it "sets @delete_agree to true if the user agrees" do
        say "y"
        subject.ask_to_delete_backup_after_restore
        expect(subject.delete_agree).to eq(true)
      end

      it "sets @delete_agree to false if the user disagrees" do
        say "n"
        subject.ask_to_delete_backup_after_restore
        expect(subject.delete_agree).to eq(false)
      end
    end

    context "when @backup_type not is LOCAL_FILE" do
      let(:uri) { described_class::DB_RESTORE_FILE }

      before do
        subject.instance_variable_set(:@uri, uri)
        subject.instance_variable_set(:@backup_type, described_class::NFS_FILE)
      end

      it "no-ops" do
        subject.ask_to_delete_backup_after_restore
        expect_output ""
      end
    end

    describe "#confirm_and_execute" do
      let(:uri)             { "/tmp/my_db.backup" }
      let(:agree)           { "y" }
      let(:task)            { "evm:db:restore:local" }
      let(:task_params)     { ["--", { :uri => uri }] }
      let(:utils)           { ManageIQ::ApplianceConsole::Utilities }

      before do
        subject.instance_variable_set(:@uri, uri)
        subject.instance_variable_set(:@delete_agree, true)
        expect(STDIN).to receive(:getc)
        allow(File).to receive(:delete)
      end

      def confirm_and_execute
        say agree
        subject.confirm_and_execute
      end

      context "when it is successful" do
        before { expect(utils).to receive(:rake).and_return(true) }

        it "deletes the backup file" do
          expect(File).to receive(:delete).with(uri).once
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
            Are you sure you would like to restore the database? (Y/N): 
            Restoring the database...

            Removing the database restore file #{uri}...

            Press any key to continue.
          PROMPT
        end

        context "without a delete agreement" do
          before do
            subject.instance_variable_set(:@delete_agree, false)
          end

          it "does not delete the backup file" do
            expect(File).to receive(:delete).with(uri).never
            confirm_and_execute
          end

          it "outputs waits for user to press a key to continue" do
            confirm_and_execute
            expect_output <<-PROMPT.strip_heredoc

              Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
              Are you sure you would like to restore the database? (Y/N): 
              Restoring the database...

              Press any key to continue.
            PROMPT
          end
        end
      end

      context "when it is not successful" do
        before { expect(utils).to receive(:rake).and_return(false) }

        it "does not delete the backup file" do
          expect(File).to receive(:delete).with(uri).never
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
            Are you sure you would like to restore the database? (Y/N): 
            Restoring the database...

            Database restore failed. Check the logs for more information

            Press any key to continue.
          PROMPT
        end

        context "without a delete agreement" do
          before do
            subject.instance_variable_set(:@delete_agree, false)
          end

          it "does not delete the backup file" do
            expect(File).to receive(:delete).with(uri).never
            confirm_and_execute
          end

          it "outputs waits for user to press a key to continue" do
            confirm_and_execute
            expect_output <<-PROMPT.strip_heredoc

              Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
              Are you sure you would like to restore the database? (Y/N): 
              Restoring the database...

              Database restore failed. Check the logs for more information

              Press any key to continue.
            PROMPT
          end
        end
      end

      context "when the user aborts" do
        let(:agree) { 'n' }

        it "does not delete the backup file" do
          expect(File).to  receive(:delete).with(uri).never
          expect(utils).to receive(:rake).never
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
            Are you sure you would like to restore the database? (Y/N): 
            Press any key to continue.
          PROMPT
        end
      end
    end
  end
end
