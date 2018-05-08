require 'manageiq/appliance_console/errors'

module ManageIQ
  module ApplianceConsole
    module UI
      class DatabaseAdmin < HighLine
        include ManageIQ::ApplianceConsole::Prompts

        LOCAL_FILE     = "Local file".freeze
        NFS_FILE       = "Network File System (NFS)".freeze
        SMB_FILE       = "Samba (SMB)".freeze
        FILE_OPTIONS   = [LOCAL_FILE, NFS_FILE, SMB_FILE, CANCEL].freeze

        DB_RESTORE_FILE      = "/tmp/evm_db.backup".freeze
        LOCAL_FILE_VALIDATOR = ->(a) { File.exist?(a) }.freeze

        NFS_PROMPT = <<-PROMPT.strip_heredoc.chomp
          location of the remote backup file
          Example: #{SAMPLE_URLS['nfs']}
        PROMPT
        SMB_PROMPT = <<-PROMPT.strip_heredoc.chomp
          location of the remote backup file
          Example: #{SAMPLE_URLS['smb']}
        PROMPT
        USER_PROMPT = <<-PROMPT.strip_heredoc.chomp
          username with access to this file.
          Example: 'mydomain.com/user'
        PROMPT

        attr_reader :action, :backup_type, :task, :task_params, :delete_agree, :uri

        def self.run(action)
          new(action).run
        end

        def initialize(action = :restore, input = $stdin, output = $stdout)
          super(input, output)

          @action      = action
          @task_params = []
        end

        def run
          setting_header
          ask_file_location

          clear_screen
          setting_header

          ask_to_delete_backup_after_restore
          confirm_and_execute
        end

        def ask_file_location
          case @backup_type = ask_with_menu(*file_menu_args)
          when LOCAL_FILE then ask_local_file_options
          when NFS_FILE   then ask_nfs_file_options
          when SMB_FILE   then ask_smb_file_options
          when CANCEL     then raise MiqSignalError
          end
        end

        def ask_local_file_options
          @uri = just_ask("location of the local restore file",
                          DB_RESTORE_FILE, LOCAL_FILE_VALIDATOR,
                          "file that exists")

          @task        = "evm:db:#{action}:local"
          @task_params = ["--", {:local_file => uri}]
        end

        def ask_nfs_file_options
          @uri         = ask_for_uri(NFS_PROMPT, "nfs")
          @task        = "evm:db:#{action}:remote"
          @task_params = ["--", {:uri => @uri}]
        end

        def ask_smb_file_options
          @uri         = ask_for_uri(SMB_PROMPT, "smb")
          user         = just_ask(USER_PROMPT)
          pass         = ask_for_password("password for #{user}")

          @task        = "evm:db:#{action}:remote"
          @task_params = [
            "--",
            {
              :uri          => @uri,
              :uri_username => user,
              :uri_password => pass
            }
          ]
        end

        def ask_to_delete_backup_after_restore
          if action == :restore && backup_type == LOCAL_FILE
            say("The local database restore file is located at: '#{uri}'.\n")
            @delete_agree = agree("Should this file be deleted after completing the restore? (Y/N): ")
          end
        end

        def confirm_and_execute
          if action == :backup || agree_to_restore?
            say("\n#{action == :restore ? "Restoring the database" : "Running Database backup to #{uri}"}...")
            rake_success = ManageIQ::ApplianceConsole::Utilities.rake(task, task_params)
            if rake_success && action == :restore && delete_agree
              say("\nRemoving the database restore file #{uri}...")
              File.delete(uri)
            elsif !rake_success
              say("\nDatabase #{action} failed. Check the logs for more information")
            end
          end
          press_any_key
        end

        def agree_to_restore?
          say("\nNote: A database restore cannot be undone.  The restore will use the file: #{uri}.\n")
          agree("Are you sure you would like to restore the database? (Y/N): ")
        end

        def file_menu_args
          [
            action == :restore ? "Restore Database File" : "Backup File Location",
            FILE_OPTIONS,
            LOCAL_FILE,
            nil
          ]
        end

        def setting_header
          say("#{I18n.t("advanced_settings.db#{action}")}\n\n")
        end
      end
    end
  end
end
