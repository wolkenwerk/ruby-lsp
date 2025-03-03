# typed: strict
# frozen_string_literal: true

require "ruby_lsp/document"

module RubyLsp
  class Store
    extend T::Sig

    sig { returns(String) }
    attr_accessor :encoding

    sig { returns(String) }
    attr_accessor :formatter

    sig { void }
    def initialize
      @state = T.let({}, T::Hash[String, Document])
      @encoding = T.let(Constant::PositionEncodingKind::UTF8, String)
      @formatter = T.let("auto", String)
    end

    sig { params(uri: URI::Generic).returns(Document) }
    def get(uri)
      path = unescaped_uri_path(uri)
      document = @state[path]
      return document unless document.nil?

      set(uri: uri, source: File.binread(CGI.unescape(path)), version: 0)
      T.must(@state[path])
    end

    sig { params(uri: URI::Generic, source: String, version: Integer).void }
    def set(uri:, source:, version:)
      document = Document.new(source: source, version: version, uri: uri, encoding: @encoding)
      @state[unescaped_uri_path(uri)] = document
    end

    sig { params(uri: URI::Generic, edits: T::Array[Document::EditShape], version: Integer).void }
    def push_edits(uri:, edits:, version:)
      T.must(@state[unescaped_uri_path(uri)]).push_edits(edits, version: version)
    end

    sig { void }
    def clear
      @state.clear
    end

    sig { returns(T::Boolean) }
    def empty?
      @state.empty?
    end

    sig { params(uri: URI::Generic).void }
    def delete(uri)
      @state.delete(unescaped_uri_path(uri))
    end

    sig do
      type_parameters(:T)
        .params(
          uri: URI::Generic,
          request_name: String,
          block: T.proc.params(document: Document).returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
    end
    def cache_fetch(uri, request_name, &block)
      get(uri).cache_fetch(request_name, &block)
    end

    private

    sig { params(uri: URI::Generic).returns(String) }
    def unescaped_uri_path(uri)
      # When a file was written to disk, we get a file URI. If it's a temporary file, then the URI is
      # `untitled:Untitled-1`, where the scheme is `untitled` and the opaque is the name of the temporary file (e.g.
      # `Untitled-1`).
      path = uri.path
      path ||= uri.opaque
      CGI.unescape(path)
    end
  end
end
