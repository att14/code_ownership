# frozen_string_literal: true

# typed: true

module CodeOwnership
  module Private
    module OwnershipMappers
      class DirectoryOwnership
        extend T::Sig
        include Mapper

        CODEOWNERS_DIRECTORY_FILE_NAME = '.codeowner'
        RELATIVE_ROOT = Pathname('.').freeze
        ABSOLUTE_ROOT = Pathname('/').freeze

        @@directory_cache = T.let({}, T::Hash[String, T.nilable(CodeTeams::Team)]) # rubocop:disable Style/ClassVars

        sig do
          override.params(file: String).
            returns(T.nilable(::CodeTeams::Team))
        end
        def map_file_to_owner(file)
          map_file_to_relevant_owner(file)
        end

        sig do
          override.params(cache: GlobsToOwningTeamMap, files: T::Array[String]).returns(GlobsToOwningTeamMap)
        end
        def update_cache(cache, files)
          globs_to_owner(files)
        end

        #
        # Directory ownership ignores the passed in files when generating code owners lines.
        # This is because Directory ownership knows that the fastest way to find code owners for directory based ownership
        # is to simply iterate over the directories and grab the owner, rather than iterating over each file just to get what directory it is in
        # In theory this means that we may generate code owners lines that cover files that are not in the passed in argument,
        # but in practice this is not of consequence because in reality we never really want to generate code owners for only a
        # subset of files, but rather we want code ownership for all files.
        #
        sig do
          override.params(files: T::Array[String]).
            returns(T::Hash[String, ::CodeTeams::Team])
        end
        def globs_to_owner(files)
          # The T.unsafe is because the upstream RBI is wrong for Pathname.glob
          T
            .unsafe(Pathname)
            .glob(File.join('**/', CODEOWNERS_DIRECTORY_FILE_NAME))
            .map(&:cleanpath)
            .each_with_object({}) do |pathname, res|
            owner = owner_for_codeowners_file(pathname)
            res[pathname.dirname.cleanpath.join('**/**').to_s] = owner
          end
        end

        sig { override.returns(String) }
        def description
          'Owner in .codeowner'
        end

        sig { override.void }
        def bust_caches!
          @@directory_cache = {} # rubocop:disable Style/ClassVars
        end

        private

        sig { params(codeowners_file: Pathname).returns(CodeTeams::Team) }
        def owner_for_codeowners_file(codeowners_file)
          raw_owner_value = File.foreach(codeowners_file).first.strip

          Private.find_team!(
            raw_owner_value,
            codeowners_file.to_s
          )
        end

        # Takes a file and finds the relevant `.codeowner` file by walking up the directory
        # structure. Example, given `a/b/c.rb`, this looks for `a/b/.codeowner`, `a/.codeowner`,
        # and `.codeowner` in that order, stopping at the first file to actually exist.
        # If the parovided file is a directory, it will look for `.codeowner` in that directory and then upwards.
        # We do additional caching so that we don't have to check for file existence every time.
        sig { params(file: String).returns(T.nilable(CodeTeams::Team)) }
        def map_file_to_relevant_owner(file)
          file_path = Pathname.new(file)
          team = T.let(nil, T.nilable(CodeTeams::Team))

          if File.directory?(file)
            team = get_team_from_codeowners_file_within_directory(file_path)
          end

          while team.nil? && file_path != RELATIVE_ROOT && file_path != ABSOLUTE_ROOT
            file_path = file_path.parent
            team = get_team_from_codeowners_file_within_directory(file_path)
          end

          team
        end

        sig { params(directory: Pathname).returns(T.nilable(CodeTeams::Team)) }
        def get_team_from_codeowners_file_within_directory(directory)
          potential_codeowners_file = directory.join(CODEOWNERS_DIRECTORY_FILE_NAME)

          potential_codeowners_file_name = potential_codeowners_file.to_s

          team = nil
          if @@directory_cache.key?(potential_codeowners_file_name)
            team = @@directory_cache[potential_codeowners_file_name]
          elsif potential_codeowners_file.exist?
            team = owner_for_codeowners_file(potential_codeowners_file)

            @@directory_cache[potential_codeowners_file_name] = team
          else
            @@directory_cache[potential_codeowners_file_name] = nil
          end

          return team
        end
      end
    end
  end
end
