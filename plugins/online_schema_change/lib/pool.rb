# JetCollins monkeypatches to add Collins integration

module Jetpants
  class Pool

    def alter_table(database, table, alter, dry_run=true, force=false, no_check_plan=false)
      database ||= app_schema
      error = false

      raise "not enough space to run alter table on #{table}" unless master.has_space_for_alter?(table, database)

      if Jetpants.plugin_enabled? 'jetpants_collins'
        raise "alter table already running on #{@name}" unless check_collins_for_alter
        update_collins_for_alter(database, table, alter)
      end

      max_threads = max_threads_running(30,1)
      max_threads = 50 unless max_threads > 50

      critical_threads_running = 2 * max_threads > 500 ? 2 * max_threads : 500

      check_plan = no_check_plan ? "--nocheck-plan" : ""

      master.with_online_schema_change_user('pt-osc', database) do |password|

        command = "pt-online-schema-change --nocheck-replication-filters --max-load='Threads_running:#{max_threads}' --critical-load='Threads_running:#{critical_threads_running}' --nodrop-old-table --nodrop-new-table --set-vars='wait_timeout=100000' #{check_plan} --dry-run --print --alter '#{alter}' D=#{database},t=#{table},h=#{master.ip},u=#{'pt-osc'},p=#{password}"

        print "[#{@name.to_s.red}][#{Time.now.to_s.blue}]---------------------------------------------------------------------------------------\n"
        print "[#{@name.to_s.red}][#{Time.now.to_s.blue}] #{command}\n"
        print "[#{@name.to_s.red}][#{Time.now.to_s.blue}]---------------------------------------------------------------------------------------\n"

        IO.popen command do |io|
          io.each do |line|
            print "[#{@name.to_s.red}][#{Time.now.to_s.blue}] #{line.gsub("\n","")}\n"
          end
          error = true if $?.to_i > 0
        end

        if !(dry_run || error)
          continue = 'no'
          unless force
            continue = ask('Dry run complete would you like to continue?: (YES/no)')
          end

          if force || continue == 'YES'
            command = "pt-online-schema-change --nocheck-replication-filters --max-load='Threads_running:#{max_threads}' --critical-load='Threads_running:#{critical_threads_running}' --nodrop-old-table --nodrop-new-table --set-vars='wait_timeout=100000' #{check_plan} --execute --print --alter '#{alter}' D=#{database},t=#{table},h=#{master.ip},u=#{'pt-osc'},p=#{password}"
            
            print "[#{@name.to_s.red}][#{Time.now.to_s.blue}]---------------------------------------------------------------------------------------\n\n\n"
            print "[#{@name.to_s.red}][#{Time.now.to_s.blue}] #{command}\n"
            print "[#{@name.to_s.red}][#{Time.now.to_s.blue}]\n\n---------------------------------------------------------------------------------------\n\n\n"

            IO.popen command do |io|
              io.each do |line|
                print "[#{@name.to_s.red}][#{Time.now.to_s.blue}] #{line.gsub("\n","")}\n"
              end
              error = true if $?.to_i > 0
            end #end execute

          end #end continue
        
        end #end if ! dry run

      end #end user grant block

      if Jetpants.plugin_enabled? 'jetpants_collins'
        clean_up_collins_for_alter
      end

      ! error
    end

    # drop old table after an alter, this is because
    # we do not drop the table after an alter
    def drop_old_alter_table(database, table)
      database ||= app_schema
      master.mysql_root_cmd("USE #{database}; DROP TABLE IF EXISTS _#{table}_old")
    end

  end
end
