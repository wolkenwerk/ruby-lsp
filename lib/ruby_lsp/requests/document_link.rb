# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/source_uri"

module RubyLsp
  module Requests
    # ![Document link demo](../../document_link.gif)
    #
    # The [document link](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentLink)
    # makes `# source://PATH_TO_FILE#line` comments in a Ruby/RBI file clickable if the file exists.
    # When the user clicks the link, it'll open that location.
    #
    # # Example
    #
    # ```ruby
    # # source://syntax_tree/3.2.1/lib/syntax_tree.rb#51 <- it will be clickable and will take the user to that location
    # def format(source, maxwidth = T.unsafe(nil))
    # end
    # ```
    class DocumentLink < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::DocumentLink] } }

      GEM_TO_VERSION_MAP = T.let(
        [*::Gem::Specification.default_stubs, *::Gem::Specification.stubs].map! do |s|
          [s.name, s.version.to_s]
        end.to_h.freeze,
        T::Hash[String, String],
      )

      class << self
        extend T::Sig

        sig { returns(T::Hash[String, T::Hash[String, T::Hash[String, String]]]) }
        def gem_paths
          @gem_paths ||= T.let(
            begin
              lookup = {}

              Gem::Specification.stubs.each do |stub|
                spec = stub.to_spec
                lookup[spec.name] = {}
                lookup[spec.name][spec.version.to_s] = {}

                Dir.glob("**/*.rb", base: "#{spec.full_gem_path}/").each do |path|
                  lookup[spec.name][spec.version.to_s][path] = "#{spec.full_gem_path}/#{path}"
                end
              end

              Gem::Specification.default_stubs.each do |stub|
                spec = stub.to_spec
                lookup[spec.name] = {}
                lookup[spec.name][spec.version.to_s] = {}
                prefix_matchers = Regexp.union(spec.require_paths.map do |rp|
                                                 Regexp.new("^#{rp}/")
                                               end)
                prefix_matcher = Regexp.union(prefix_matchers, //)

                spec.files.each do |file|
                  path = file.sub(prefix_matcher, "")
                  lookup[spec.name][spec.version.to_s][path] = "#{RbConfig::CONFIG["rubylibdir"]}/#{path}"
                end
              end

              lookup
            end,
            T.nilable(T::Hash[String, T::Hash[String, T::Hash[String, String]]]),
          )
        end
      end

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(uri: URI::Generic, emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(uri, emitter, message_queue)
        super(emitter, message_queue)

        # Match the version based on the version in the RBI file name. Notice that the `@` symbol is sanitized to `%40`
        # in the URI
        version_match = uri.path ? /(?<=%40)[\d.]+(?=\.rbi$)/.match(CGI.unescape(uri.path)) : nil
        @gem_version = T.let(version_match && version_match[0], T.nilable(String))
        @response = T.let([], T::Array[Interface::DocumentLink])

        emitter.register(self, :on_comment)
      end

      sig { params(node: SyntaxTree::Comment).void }
      def on_comment(node)
        match = node.value.match(%r{source://.*#\d+$})
        return unless match

        uri = T.cast(URI(T.must(match[0])), URI::Source)
        gem_version = T.must(resolve_version(uri))
        file_path = self.class.gem_paths.dig(uri.gem_name, gem_version, CGI.unescape(uri.path))
        return if file_path.nil?

        @response << Interface::DocumentLink.new(
          range: range_from_syntax_tree_node(node),
          target: "file://#{file_path}##{uri.line_number}",
          tooltip: "Jump to #{file_path}##{uri.line_number}",
        )
      end

      private

      # Try to figure out the gem version for a source:// link. The order of precedence is:
      # 1. The version in the URI
      # 2. The version in the RBI file name
      # 3. The version from the gemspec
      sig { params(uri: URI::Source).returns(T.nilable(String)) }
      def resolve_version(uri)
        version = uri.gem_version
        return version unless version.nil? || version.empty?

        return @gem_version unless @gem_version.nil? || @gem_version.empty?

        GEM_TO_VERSION_MAP[uri.gem_name]
      end
    end
  end
end
