# frozen_string_literal: true

require "json"
require "digest/md5"
require "hanami/router"
require "hanami/middleware/body_parser"
require "hanami/view/html"
require_relative "renderer"

require_relative "validations"

HTTP_TEST_STATUSES = {
  100 => "Continue",
  101 => "Switching Protocols",
  102 => "Processing",
  103 => "Early Hints",
  200 => "OK",
  201 => "Created",
  202 => "Accepted",
  203 => "Non-Authoritative Information",
  204 => "No Content",
  205 => "Reset Content",
  206 => "Partial Content",
  207 => "Multi-Status",
  208 => "Already Reported",
  226 => "IM Used",
  300 => "Multiple Choices",
  301 => "Moved Permanently",
  302 => "Found",
  303 => "See Other",
  304 => "Not Modified",
  305 => "Use Proxy",
  306 => "(Unused)",
  307 => "Temporary Redirect",
  308 => "Permanent Redirect",
  400 => "Bad Request",
  401 => "Unauthorized",
  402 => "Payment Required",
  403 => "Forbidden",
  404 => "Not Found",
  405 => "Method Not Allowed",
  406 => "Not Acceptable",
  407 => "Proxy Authentication Required",
  408 => "Request Timeout",
  409 => "Conflict",
  410 => "Gone",
  411 => "Length Required",
  412 => "Precondition Failed",
  413 => "Payload Too Large",
  414 => "URI Too Long",
  415 => "Unsupported Media Type",
  416 => "Range Not Satisfiable",
  417 => "Expectation Failed",
  421 => "Misdirected Request",
  422 => "Unprocessable Entity",
  423 => "Locked",
  424 => "Failed Dependency",
  425 => "Too Early",
  426 => "Upgrade Required",
  428 => "Precondition Required",
  429 => "Too Many Requests",
  431 => "Request Header Fields Too Large",
  451 => "Unavailable for Legal Reasons",
  500 => "Internal Server Error",
  501 => "Not Implemented",
  502 => "Bad Gateway",
  503 => "Service Unavailable",
  504 => "Gateway Timeout",
  505 => "HTTP Version Not Supported",
  506 => "Variant Also Negotiates",
  507 => "Insufficient Storage",
  508 => "Loop Detected",
  509 => "Bandwidth Limit Exceeded",
  510 => "Not Extended",
  511 => "Network Authentication Required"
}.freeze
HTTP_TEST_STATUSES_WITHOUT_BODY = (((100..199).to_a << 204 << 304) & HTTP_TEST_STATUSES.keys).freeze

class RecordNotFound < StandardError
end

module Test
  class Index < Hanami::Action
    def handle(req, res)
      res[:xyz] = req.params[:name]
    end
  end
end

class CallAction < Hanami::Action
  def handle(_req, res)
    res.status = 201
    res.body   = "Hi from TestAction!"
    res.headers.merge!("X-Custom" => "OK")
  end
end

class UncheckedErrorCallAction < Hanami::Action
  def handle(_req, _res)
    raise
  end
end

class ErrorCallAction < Hanami::Action
  config.handle_exception RuntimeError => 500

  def handle(_req, _res)
    raise
  end
end

class MyCustomError < StandardError; end

class ErrorCallFromInheritedErrorClass < Hanami::Action
  config.handle_exception StandardError => :handler

  def handle(*)
    raise MyCustomError
  end

  private

  def handler(_req, res, *)
    res.status = 501
    res.body   = "An inherited exception occurred!"
  end
end

class ErrorCallFromInheritedErrorClassStack < Hanami::Action
  config.handle_exception StandardError => :standard_handler
  config.handle_exception MyCustomError => :handler

  def handle(*)
    raise MyCustomError
  end

  private

  def handler(_req, res, *)
    res.status = 501
    res.body   = "MyCustomError was thrown"
  end

  def standard_handler(_req, res, *)
    res.status = 501
    res.body   = "An unknown error was thrown"
  end
end

class ErrorCallWithSymbolMethodNameAsHandlerAction < Hanami::Action
  config.handle_exception StandardError => :handler

  def handle(*)
    raise StandardError
  end

  private

  def handler(_req, res, *)
    res.status = 501
    res.body   = "Please go away!"
  end
end

class ErrorCallWithStringMethodNameAsHandlerAction < Hanami::Action
  config.handle_exception StandardError => "standard_error_handler"

  def handle(*)
    raise StandardError
  end

  private

  def standard_error_handler(_req, res, exception)
    res.status = 502
    res.body   = exception.message
  end
end

class ErrorCallWithUnsetStatusResponse < Hanami::Action
  config.handle_exception ArgumentError => "arg_error_handler"

  def handle(*)
    raise ArgumentError
  end

  private

  def arg_error_handler(*)
  end
end

class ErrorCallWithSpecifiedStatusCodeAction < Hanami::Action
  config.handle_exception StandardError => 422

  def handle(_req, _res)
    raise StandardError
  end
end

class BeforeMethodAction < Hanami::Action
  before :set_article, :reverse_article, :log_request
  append_before :add_first_name_to_logger, :add_last_name_to_logger
  prepend_before :add_title_to_logger

  def handle(req, res)
  end

  private

  def set_article(*, res)
    res[:article] = "Bonjour!"
  end

  def reverse_article(*, res)
    res[:article] = res[:article].reverse
  end

  def log_request(req, res)
    res[:arguments] = []
    res[:arguments] << req.class.name
    res[:arguments] << res.class.name
  end

  def add_first_name_to_logger(*, res)
    res[:logger] << "John"
  end

  def add_last_name_to_logger(*, res)
    res[:logger] << "Doe"
  end

  def add_title_to_logger(*, res)
    res[:logger] = []
    res[:logger] << "Mr."
  end
end

class SubclassBeforeMethodAction < BeforeMethodAction
  before :upcase_article

  private

  def upcase_article
    @article.upcase!
  end
end

class ParamsBeforeMethodAction < BeforeMethodAction
  private

  def upcase_article
  end

  def set_article(req, res)
    res[:exposed_params] = req.params
    res[:article] = super + req.params[:bang]
  end
end

class ErrorBeforeMethodAction < BeforeMethodAction
  private

  def set_article
    raise
  end
end

class HandledErrorBeforeMethodAction < BeforeMethodAction
  config.handle_exception RecordNotFound => 404

  private

  def set_article
    raise RecordNotFound.new
  end
end

class BeforeBlockAction < Hanami::Action
  before { |_, res|   res[:article] = "Good morning!" }
  before { |_, res|   res[:article] = res[:article].reverse }
  before { |req, res| res[:arguments] = [req.class.name, res.class.name] }

  def handle(req, res)
  end
end

class YieldBeforeBlockAction < BeforeBlockAction
  before { |req, res| res[:yielded_params] = req.params }
end

class AfterMethodAction < Hanami::Action
  after :set_egg, :scramble_egg, :log_request
  append_after :add_first_name_to_logger, :add_last_name_to_logger
  prepend_after :add_title_to_logger

  def handle(*)
  end

  private

  def set_egg(*, res)
    res[:egg] = "Egg!"
  end

  def scramble_egg(*, res)
    res[:egg] = "gE!g"
  end

  def log_request(req, res)
    res[:arguments] = []
    res[:arguments] << req.class.name
    res[:arguments] << res.class.name
  end

  def add_first_name_to_logger(*, res)
    res[:logger] << "Jane"
  end

  def add_last_name_to_logger(*, res)
    res[:logger] << "Dixit"
  end

  def add_title_to_logger(*, res)
    res[:logger] = []
    res[:logger] << "Mrs."
  end
end

class AfterBlockAction < Hanami::Action
  after { |_, res| res[:egg] = "Coque" }
  after { |_, res| res[:egg] = res[:egg].reverse }
  after { |req, res| res[:arguments] = [req.class.name, res.class.name] }

  def handle(*)
  end
end

class YieldAfterBlockAction < AfterBlockAction
  after { |req, res| res[:meaning_of_life_params] = req.params }

  def handle(*)
  end
end

class MissingRequestSessionAction < Hanami::Action
  def handle(req, _)
    req.session[:user_id]
  end
end

class MissingResponseSessionAction < Hanami::Action
  def handle(_, res)
    res.session[:user_id] = 23
  end
end

class MissingResponseFlashAction < Hanami::Action
  def handle(_, res)
    res.flash[:error] = "ouch"
  end
end

class SessionAction < Hanami::Action
  include Hanami::Action::Session

  def handle(req, res)
  end
end

class FlashAction < Hanami::Action
  include Hanami::Action::Session

  def handle(*, res)
    res.flash[:error] = "ouch"
  end
end

class RedirectAction < Hanami::Action
  def handle(*, res)
    res.redirect_to "/destination"
  end
end

class StatusRedirectAction < Hanami::Action
  def handle(*, res)
    res.redirect_to "/destination", status: 301
  end
end

class SafeStringRedirectAction < Hanami::Action
  def handle(*, res)
    location = Hanami::View::HTML::SafeString.new("/destination")
    res.redirect_to location
  end
end

class GetCookiesAction < Hanami::Action
  include Hanami::Action::Cookies

  def handle(*, res)
    res.body = res.cookies[:foo]
  end
end

class ChangeCookiesAction < Hanami::Action
  include Hanami::Action::Cookies

  def handle(*, res)
    res.body = res.cookies[:foo]
    res.cookies[:foo] = "baz"
  end
end

class GetDefaultCookiesAction < Hanami::Action
  include Hanami::Action::Cookies

  config.cookies = {domain: "hanamirb.org", path: "/controller", secure: true, httponly: true}

  def handle(*, res)
    res.body          = ""
    res.cookies[:bar] = "foo"
  end
end

class GetOverwrittenCookiesAction < Hanami::Action
  include Hanami::Action::Cookies

  config.cookies = {domain: "hanamirb.org", path: "/controller", secure: true, httponly: true}

  def handle(*, res)
    res.body          = ""
    res.cookies[:bar] = {value: "foo", domain: "hanamirb.com", path: "/action", secure: false, httponly: false}
  end
end

class GetAutomaticallyExpiresCookiesAction < Hanami::Action
  include Hanami::Action::Cookies

  def handle(*, res)
    res.cookies[:bar] = {value: "foo", max_age: 120}
  end
end

class SetCookiesAction < Hanami::Action
  include Hanami::Action::Cookies

  def handle(*, res)
    res.body          = "yo"
    res.cookies[:foo] = "yum!"
  end
end

class SetCookiesWithOptionsAction < Hanami::Action
  include Hanami::Action::Cookies

  def initialize(expires: Time.now.utc)
    @expires = expires
    super()
  end

  def handle(*, res)
    res.cookies[:kukki] =
      {value: "yum!", domain: "hanamirb.org", path: "/controller", expires: @expires, secure: true, httponly: true}
  end
end

class RemoveCookiesAction < Hanami::Action
  include Hanami::Action::Cookies

  def handle(*, res)
    res.cookies[:rm] = nil
  end
end

class IterateCookiesAction < Hanami::Action
  include Hanami::Action::Cookies

  # rubocop:disable Style/MapIntoArray
  def handle(*, res)
    result = []
    res.cookies.each do |key, value|
      result << "'#{key}' has value '#{value}'"
    end

    res.body = result.join(", ")
  end
  # rubocop:enable Style/MapIntoArray
end

class ThrowCodeAction < Hanami::Action
  def handle(req, *)
    halt req.params[:status].to_i, req.params[:message]
  end
end

class CatchAndThrowSymbolAction < Hanami::Action
  def handle(_req, _res)
    catch :done do
      throw :done, 1

      raise "This code shouldn't be reachable" # rubocop:disable Lint/UnreachableCode
    end
  end
end

class ThrowBeforeMethodAction < Hanami::Action
  before :authorize!
  before :set_body

  def handle(_req, res)
    res.body = "Hello!"
  end

  private

  def authorize!
    halt 401
  end

  def set_body
    res.body = "Hi!"
  end
end

class ThrowBeforeBlockAction < Hanami::Action
  before { halt 401 }
  before { res.body = "Hi!" }

  def handle(_req, res)
    res.body = "Hello!"
  end
end

class ThrowAfterMethodAction < Hanami::Action
  after :raise_timeout!
  after :set_body

  def handle(_req, res)
    res.body = "Hello!"
  end

  private

  def raise_timeout!
    halt 408
  end

  def set_body
    res.body = "Later!"
  end
end

class ThrowAfterBlockAction < Hanami::Action
  after { halt 408 }
  after { res.body = "Later!" }

  def handle(_req, res)
    res.body = "Hello!"
  end
end

class HandledExceptionAction < Hanami::Action
  config.handle_exception RecordNotFound => 404

  def handle(_req, _res)
    raise RecordNotFound.new
  end
end

class DomainLogicException < StandardError
end

class GlobalHandledExceptionAction < Hanami::Action
  config.handle_exception DomainLogicException => 400

  def handle(_req, _res)
    raise DomainLogicException.new
  end
end

class UnhandledExceptionAction < Hanami::Action
  def handle(_req, _res)
    raise RecordNotFound.new
  end
end

class ParamsAction < Hanami::Action
  def handle(req, res)
    params = req.params.to_h
    res.body = params.inspect
  end
end

class WhitelistedParamsAction < Hanami::Action
  class Params < Hanami::Action::Params
    params do
      if RSpec::Support::Validations.version?(2)
        required(:id).maybe(:integer)
      else
        required(:id).maybe(:int?)
      end

      required(:article).schema do
        required(:tags).each(:str?)
      end
    end
  end

  params Params

  def handle(req, res)
    res.body = req.params.to_h.inspect
  end
end

class WhitelistedDslAction < Hanami::Action
  params do
    required(:username).filled
  end

  def handle(req, res)
    res.body = req.params.to_h.inspect
  end
end

class WhitelistedUploadDslAction < Hanami::Action
  params do
    if RSpec::Support::Validations.version?(2)
      required(:id).maybe(:integer)
    else
      required(:id).maybe(:int?)
    end
    required(:upload).filled
  end

  def handle(req, res)
    res.body = req.params.to_h.inspect
  end
end

class ParamsValidationAction < Hanami::Action
  params do
    required(:email).filled(:str?)
  end

  def handle(req, *)
    halt 400 unless req.params.valid?
  end
end

class TestParams < Hanami::Action::Params
  params do
    required(:email).filled(format?: /\A.+@.+\z/)

    if RSpec::Support::Validations.version?(2)
      optional(:password).filled(:str?)
    else
      optional(:password).filled(:str?).confirmation
    end

    required(:name).filled

    if RSpec::Support::Validations.version?(2)
      required(:tos).value(:bool)
      required(:age).value(:integer)
    else
      required(:tos).filled(:bool?)
      required(:age).filled(:int?)
    end

    required(:address).schema do
      required(:line_one).filled
      required(:deep).schema do
        required(:deep_attr).filled(:str?)
      end
    end

    optional(:array).maybe do
      each do
        schema do
          required(:name).filled(:str?)
        end
      end
    end
  end
end

class NestedParams < Hanami::Action::Params
  params do
    required(:signup).schema do
      required(:name).filled(:str?)
      required(:age).filled(:int?, gteq?: 18)
    end
  end
end

class Root < Hanami::Action
  def handle(req, res)
    res.body = req.params.to_h.inspect
    res.headers.merge!("X-Test" => "test")
  end
end

module About
  class Team < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
      res.headers.merge!("X-Test" => "test")
    end
  end

  class Contacts < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end
end

module Identity
  class Show < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class New < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Create < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Edit < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Update < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Destroy < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end
end

module Flowers
  class Index < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Show < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class New < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Create < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Edit < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Update < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end

  class Destroy < Hanami::Action
    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end
end

module Painters
  class Update < Hanami::Action
    params do
      required(:painter).schema do
        required(:first_name).filled(:str?)
        required(:last_name).filled(:str?)
        optional(:paintings).maybe do
          each do
            schema do
              required(:name).filled
            end
          end
        end
      end
    end

    def handle(req, res)
      res.body = req.params.to_h.inspect
    end
  end
end

module Dashboard
  class Index < Hanami::Action
    include Hanami::Action::Session

    before :authenticate!

    def handle(*, res)
      res.body = "User ID from session: #{res.session[:user_id]}"
    end

    private

    def authenticate!(*, res)
      halt 401 unless loggedin?(res)
    end

    def loggedin?(res)
      res.session.key?(:user_id)
    end
  end
end

module Sessions
  class Create < Hanami::Action
    include Hanami::Action::Session

    def handle(*, res)
      res.session[:user_id] = 23
      res.redirect_to "/"
    end
  end

  class Destroy < Hanami::Action
    include Hanami::Action::Session

    def handle(*, res)
      res.session[:user_id] = nil
    end
  end

  class Disabled < Hanami::Action
    def handle(*, res)
      res.session[:user_id] = 23
    end
  end
end

class StandaloneSession < Hanami::Action
  include Hanami::Action::Session

  def handle(*, res)
    res.session[:age] = Time.now.year - 1982
  end
end

module Glued
  class SendFile < Hanami::Action
    def handle(_req, _res)
      send_file "test.txt"
    end
  end
end

class ArtistNotFound < StandardError
end

module App
  class CustomError < StandardError
  end

  class StandaloneAction < Hanami::Action
    config.handle_exception App::CustomError => 400

    def handle(_req, _res)
      raise App::CustomError
    end
  end
end

module App2
  class CustomError < StandardError
  end

  module Standalone
    class Index < Hanami::Action
      config.handle_exception App2::CustomError => 400

      def handle(_req, _res)
        raise App2::CustomError
      end
    end
  end
end

module MusicPlayer
  module Controllers
    module Authentication
      def self.included(action)
        action.class_eval do
          before do |_, res|
            res[:current_user] = current_user
          end
        end
      end

      private

      def current_user
        "Luca"
      end
    end

    class Dashboard
      class Index < Hanami::Action
        include Hanami::Action::Cookies
        include Hanami::Action::Session
        include MusicPlayer::Controllers::Authentication

        def handle(_req, res)
          res.body = "Muzic!"
          res.headers["X-Frame-Options"] = "ALLOW FROM https://example.org"
        end
      end

      class Show < Hanami::Action
        include Hanami::Action::Cookies
        include Hanami::Action::Session
        include MusicPlayer::Controllers::Authentication

        def handle(_req, _res)
          raise ArgumentError
        end
      end
    end

    module Artists
      class Index < Hanami::Action
        include Hanami::Action::Cookies
        include Hanami::Action::Session
        include MusicPlayer::Controllers::Authentication

        def handle(_req, res)
          res.body = current_user
        end
      end

      class Show < Hanami::Action
        include Hanami::Action::Cookies
        include Hanami::Action::Session
        include MusicPlayer::Controllers::Authentication

        config.handle_exception ArtistNotFound => 404

        def handle(_req, _res)
          raise ArtistNotFound
        end
      end
    end
  end

  class StandaloneAction < Hanami::Action
    include Hanami::Action::Cookies
    include Hanami::Action::Session
    include MusicPlayer::Controllers::Authentication

    def handle(_req, _res)
      raise ArgumentError
    end
  end

  class Application
    def initialize
      Hanami::Action.configure do |config|
        config.handle_exception ArgumentError => 400
        config.default_headers(
          "X-Frame-Options" => "DENY"
        )
      end
    end
  end
end

class VisibilityAction < Hanami::Action
  include Hanami::Action::Cookies
  include Hanami::Action::Session

  def handle(*, res)
    res.body   = "x"
    res.status = 201
    res.format = :json

    res.headers.merge!("X-Custom" => "OK", "Y-Custom" => "YO")
    res.session[:foo] = "bar"
  end
end

module SendFileTest
  module Files
    class Action < Hanami::Action
      config.public_directory = "spec/support/fixtures"
    end

    class Show < Action
      def handle(req, res)
        id = req.params[:id]

        # This if statement is only for testing purpose
        case id
        when "1"
          res.send_file Pathname.new("test.txt")
        when "2"
          res.send_file Pathname.new("hanami.png")
        when "3"
          res.send_file Pathname.new("Gemfile")
        when "100"
          res.send_file Pathname.new("unknown.txt")
        else
          # a more realistic example of globbing ':id(.:format)'

          resource = repository_dot_find_by_id(id)
          # this is usually 406, but I want to distinguish it from the 406 below.
          halt 400 unless resource
          extension = req.params[:format]

          case extension
          when "html"
            # in reality we'd render a template here, but as a test fixture, we'll simulate that answer
            # we should have also checked #accept? but w/e
            res.body = ::File.read(Pathname.new("spec/support/fixtures/#{resource.asset_path}.html"))
            res.status = 200
            res.format = :html
          when "json", nil
            res.format = :json
            res.send_file Pathname.new("#{resource.asset_path}.json")
          else
            halt 406
          end
        end
      end

      private

      Model = Struct.new(:id, :asset_path)

      def repository_dot_find_by_id(id)
        return nil unless id =~ /^\d+$/

        Model.new(id.to_i, "resource-#{id}")
      end
    end

    class UnsafeLocal < Action
      def handle(*, res)
        res.unsafe_send_file "Gemfile"
      end
    end

    class UnsafePublic < Action
      def handle(*, res)
        res.unsafe_send_file "spec/support/fixtures/test.txt"
      end
    end

    class UnsafeAbsolute < Action
      def handle(*, res)
        res.unsafe_send_file Pathname.new("Gemfile").realpath
      end
    end

    class UnsafeMissingLocal < Action
      def handle(*, res)
        res.unsafe_send_file "missing"
      end
    end

    class UnsafeMissingAbsolute < Action
      def handle(_req, res)
        res.unsafe_send_file Pathname.new(".").join("missing")
      end
    end

    class Flow < Action
      def handle(*, res)
        res.send_file Pathname.new("test.txt")
        res.redirect_to "/"
      end
    end

    class Glob < Action
      def handle(*)
        halt 202
      end
    end

    class BeforeCallback < Action
      before :before_callback

      def handle(*, res)
        res.send_file Pathname.new("test.txt")
      end

      private

      def before_callback(*, res)
        res.headers["X-Callbacks"] = "before"
      end
    end

    class AfterCallback < Action
      after :after_callback

      def handle(*, res)
        res.send_file Pathname.new("test.txt")
      end

      private

      def after_callback(*, res)
        res.headers["X-Callbacks"] = "after"
      end
    end
  end

  class Application
    def initialize
      router = Hanami::Router.new do
        get "/files/flow",                    to: Files::Flow.new
        get "/files/unsafe_local",            to: Files::UnsafeLocal.new
        get "/files/unsafe_public",           to: Files::UnsafePublic.new
        get "/files/unsafe_absolute",         to: Files::UnsafeAbsolute.new
        get "/files/unsafe_missing_local",    to: Files::UnsafeMissingLocal.new
        get "/files/unsafe_missing_absolute", to: Files::UnsafeMissingAbsolute.new
        get "/files/before_callback",         to: Files::BeforeCallback.new
        get "/files/after_callback",          to: Files::AfterCallback.new
        get "/files/:id(.:format)",           to: Files::Show.new
        get "/files/(*glob)",                 to: Files::Glob.new
      end

      @app = Rack::Builder.new do
        use Rack::Lint
        run router
      end.to_app
    end

    def call(env)
      @app.call(env)
    end
  end
end

module HeadTest
  module Home
    class Index < Hanami::Action
      include Hanami::Action::Session

      def handle(_req, res)
        res.body = "index"
      end
    end

    class Code < Hanami::Action
      include Hanami::Action::Cache
      include Hanami::Action::Session

      def handle(req, res)
        content = "code"

        res.headers.merge!(
          "Allow" => "GET, HEAD",
          "Content-Encoding" => "identity",
          "Content-Language" => "en",
          "Content-Length" => content.length,
          "Content-Location" => "relativeURI",
          "Content-MD5" => Digest::MD5.hexdigest(content),
          "Expires" => "Thu, 01 Dec 1994 16:00:00 GMT",
          "Last-Modified" => "Wed, 21 Jan 2015 11:32:10 GMT"
        )

        res.status = req.params[:code].to_i
        res.body   = "code"
      end
    end

    class Override < Hanami::Action
      include Hanami::Action::Session

      def handle(_req, res)
        res.headers.merge!(
          "Last-Modified" => "Fri, 27 Nov 2015 13:32:36 GMT",
          "X-Rate-Limit" => "4000",
          "X-No-Pass" => "true"
        )

        res.status = 204
      end

      private

      def keep_response_header?(header)
        super || header == "X-Rate-Limit"
      end
    end
  end

  class Application
    def initialize
      Hanami::Action.configure do |config|
        config.default_headers = {
          "X-Frame-Options" => "DENY"
        }
      end

      router = Hanami::Router.new do
        get "/",           to: Home::Index.new
        get "/code/:code", to: Home::Code.new
        get "/override",   to: Home::Override.new
      end

      @app = Rack::Builder.new do
        use Rack::Session::Cookie, secret: SecureRandom.hex(16)
        run router
      end.to_app
    end

    def call(env)
      @app.call(env)
    end
  end
end

module FullStack
  module Controllers
    module Home
      class Index < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(*, res)
          res[:greeting] = "Hello"
        end
      end

      class Head < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(*, res)
          res.body = "foo"
        end
      end
    end

    module Books
      class Index < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(*)
        end
      end

      class Create < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        params do
          required(:title).filled(:str?)
        end

        def handle(req, res)
          req.params.valid?

          res.redirect_to "/books"
        end
      end

      class Update < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        params do
          if RSpec::Support::Validations.version?(2)
            required(:id).value(:integer)
          else
            required(:id).value(:int?)
          end

          required(:book).schema do
            required(:title).filled(:str?)
            required(:author).schema do
              required(:name).filled(:str?)
              required(:favourite_colour)
            end
          end
        end

        def handle(req, res)
          valid = req.params.valid?

          res.status = 201
          res.body = JSON.generate(
            symbol_access: req.params[:book][:author] && req.params[:book][:author][:name],
            valid: valid,
            errors: req.params.errors.to_h
          )
        end
      end
    end

    module Settings
      class Index < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(*)
        end
      end

      class Create < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(*, res)
          res.flash[:message] = "Saved!"
          res.redirect_to "/settings"
        end
      end
    end

    module Poll
      class Start < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(*, res)
          res.redirect_to "/poll/1"
        end
      end

      class Step1 < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(req, res)
          if req.env["REQUEST_METHOD"] == "GET"
            res.flash[:notice] = "Start the poll"
          else
            res.flash[:notice] = "Step 1 completed"
            res.redirect_to "/poll/2"
          end
        end
      end

      class Step2 < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(req, res)
          if req.env["REQUEST_METHOD"] == "POST"
            res.flash[:notice] = "Poll completed"
            res.redirect_to "/"
          end
        end
      end
    end

    module Users
      class Show < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        before :redirect_to_root
        after :set_body

        def handle(*, res)
          res.body = "call method shouldn't be called"
        end

        private

        def redirect_to_root(*, res)
          res.redirect_to "/"
        end

        def set_body
          res.body = "after callback shouldn't be called"
        end
      end
    end
  end

  class Application
    def initialize
      routes = Hanami::Router.new do
        get "/",     to: FullStack::Controllers::Home::Index.new
        get "/head", to: FullStack::Controllers::Home::Head.new
        resources :books, only: %i[index create update]

        get  "/settings", to: FullStack::Controllers::Settings::Index.new
        post "/settings", to: FullStack::Controllers::Settings::Create.new

        get "/poll", to: FullStack::Controllers::Poll::Start.new

        prefix "poll" do
          get  "/1", to: FullStack::Controllers::Poll::Step1.new
          post "/1", to: FullStack::Controllers::Poll::Step1.new
          get  "/2", to: FullStack::Controllers::Poll::Step2.new
          post "/2", to: FullStack::Controllers::Poll::Step2.new
        end

        prefix "users" do
          get "/1", to: FullStack::Controllers::Users::Show.new
        end
      end

      @renderer = Renderer.new
      @app      = Rack::Builder.new do
        use Rack::Session::Cookie, secret: SecureRandom.hex(16)
        run routes
      end.to_app
    end

    def call(env)
      @renderer.render(env, @app.call(env))
    end
  end
end

class MethodInspectionAction < Hanami::Action
  def handle(req, res)
    res.body = req.request_method
  end
end

class RackExceptionAction < Hanami::Action
  class TestException < ::StandardError
  end

  def handle(_req, _res)
    raise TestException.new
  end
end

class HandledRackExceptionAction < Hanami::Action
  class TestException < ::StandardError
  end

  config.handle_exception TestException => 500

  def handle(_req, _res)
    raise TestException.new
  end
end

class HandledRackExceptionSubclassAction < Hanami::Action
  class TestException < ::StandardError
  end

  class TestSubclassException < TestException
  end

  config.handle_exception TestException => 500

  def handle(_req, _res)
    raise TestSubclassException.new
  end
end

module SessionWithCookies
  module Controllers
    module Home
      class Index < Hanami::Action
        include Hanami::Action::Session
        include Hanami::Action::Cookies

        def handle(req, res)
        end
      end
    end
  end

  class Application
    def initialize
      resolver = EndpointResolver.new(namespace: SessionWithCookies::Controllers)
      routes   = Hanami::Router.new(resolver: resolver) do
        get "/", to: SessionWithCookies::Controllers::Home::Index.new
      end

      @renderer = Renderer.new
      @app = Rack::Builder.new do
        use Rack::Lint
        use Rack::Session::Cookie, secret: SecureRandom.hex(16)
        run routes
      end.to_app
    end

    def call(env)
      @renderer.render(env, @app.call(env))
    end
  end
end

module SessionsWithoutCookies
  module Controllers
    module Home
      class Index < Hanami::Action
        include Hanami::Action::Session
        include Inspector

        def handle(*)
        end
      end
    end
  end

  class Application
    def initialize
      routes = Hanami::Router.new do
        get "/", to: SessionsWithoutCookies::Controllers::Home::Index.new
      end

      @renderer = Renderer.new
      @app      = Rack::Builder.new do
        use Rack::Session::Cookie, secret: SecureRandom.hex(16)
        run routes
      end.to_app
    end

    def call(env)
      @renderer.render(env, @app.call(env))
    end
  end
end

module Mimes
  class Default < Hanami::Action
    def handle(_req, res)
      res.body = res.format
    end
  end

  class Custom < Hanami::Action
    def handle(_req, res)
      res.format = :xml
      res.body   = res.format
    end
  end

  class Latin < Hanami::Action
    def handle(_req, res)
      res.charset = "latin1"
      res.format  = :html
      res.body    = res.format
    end
  end

  class Accept < Hanami::Action
    def handle(req, res)
      res.headers["X-AcceptDefault"] = req.accept?("application/octet-stream").to_s
      res.headers["X-AcceptHtml"]    = req.accept?("text/html").to_s
      res.headers["X-AcceptXml"]     = req.accept?("application/xml").to_s
      res.headers["X-AcceptJson"]    = req.accept?("text/json").to_s

      res.body = res.format
    end
  end

  class CustomFromAccept < Hanami::Action
    config.formats.add :custom, "application/custom"

    format :json, :custom

    def handle(*, res)
      res.body = res.format
    end
  end

  class Restricted < Hanami::Action
    config.formats.add :custom, "application/custom"

    format :html, :json, :custom

    def handle(_req, res)
      res.body = res.format
    end
  end

  class NoContent < Hanami::Action
    def handle(_req, res)
      res.status = 204
    end
  end

  class Strict < Hanami::Action
    format :json

    def handle(_req, res)
      res.body = res.format
    end
  end

  class Relaxed < Hanami::Action
    format :all

    def handle(_req, res)
      res.body = res.format
    end
  end

  class Application
    def initialize
      @router = Hanami::Router.new do
        get "/",                   to: Mimes::Default.new
        get "/custom",             to: Mimes::Custom.new
        get "/accept",             to: Mimes::Accept.new
        get "/restricted",         to: Mimes::Restricted.new
        get "/latin",              to: Mimes::Latin.new
        get "/nocontent",          to: Mimes::NoContent.new
        get "/custom_from_accept", to: Mimes::CustomFromAccept.new
        get "/strict",             to: Mimes::Strict.new
        get "/relaxed",            to: Mimes::Relaxed.new
      end
    end

    def call(env)
      @router.call(env)
    end
  end
end

module MimesWithDefault
  class Default < Hanami::Action
    config.format :html, :json

    def handle(*, res)
      res.body = res.format
    end
  end

  class Application
    def initialize
      @router = Hanami::Router.new do
        get "/default_and_accept", to: MimesWithDefault::Default.new
      end
    end

    def call(env)
      @router.call(env)
    end
  end
end

module RouterIntegration
  class Application
    def initialize
      routes = Hanami::Router.new do
        get "/",         to: Root.new
        get "/team",     to: About::Team.new
        get "/contacts", to: About::Contacts.new

        resource  :identity
        resources :flowers
        resources :painters, only: [:update]
      end

      @app = Rack::Builder.new do
        use Rack::Lint
        use Hanami::Middleware::BodyParser, :json
        run routes
      end.to_app
    end

    def call(env)
      @app.call(env)
    end
  end
end

module SessionIntegration
  class Application
    def initialize
      resolver = EndpointResolver.new

      routes = Hanami::Router.new(resolver: resolver) do
        get    "/",       to: Dashboard::Index.new
        post   "/login",  to: Session::Create.new
        delete "/logout", to: Sessions::Destroy.new
      end

      @app = Rack::Builder.new do
        use Rack::Lint
        use Rack::Session::Cookie, secret: SecureRandom.hex(16)
        run routes
      end.to_app
    end

    def call(env)
      @app.call(env)
    end
  end
end

module StandaloneSessionIntegration
  class Application
    def initialize
      @app = Rack::Builder.new do
        use Rack::Lint
        use Rack::Session::Cookie, secret: SecureRandom.hex(16)
        run StandaloneSession.new
      end
    end

    def call(env)
      @app.call(env)
    end
  end
end

module Flash
  module Controllers
    module Home
      class Index < Hanami::Action
        include Hanami::Action::Session

        def handle(req, res)
          res.flash[:hello] = "world"

          if req.env["REQUEST_METHOD"] == "GET"
            res.redirect_to "/books"
          else
            res.redirect_to "/print"
          end
        end
      end

      class Books < Hanami::Action
        include Hanami::Action::Session

        def handle(_, res)
          res.body = "flash_empty: #{res.flash.empty?} flash: #{res.flash.inspect}"
        end
      end

      class Print < Hanami::Action
        include Hanami::Action::Session

        def handle(_, res)
          res.body = res.flash[:hello]
        end
      end

      class EachRedirect < Hanami::Action
        include Hanami::Action::Session

        def handle(_, res)
          res.flash[:hello] = "world"
          res.redirect_to "/each"
        end
      end

      class Each < Hanami::Action
        include Hanami::Action::Session

        def handle(_, res)
          each_result = res.flash.map { |type, message| [type, message] }
          res.body = "flash_each: #{each_result}"
        end
      end

      class MapRedirect < Hanami::Action
        include Hanami::Action::Session

        def handle(_, res)
          res.flash[:hello] = "world"
          res.redirect_to "/map"
        end
      end

      class Map < Hanami::Action
        include Hanami::Action::Session

        def handle(_, res)
          res.body = "flash_map: #{res.flash.map { |type, message| [type, message] }}"
        end
      end

      class Disabled < Hanami::Action
        def handle(_, res)
          res.flash[:error] = "ouch"
        end
      end
    end
  end

  class Application
    def initialize
      routes = Hanami::Router.new do
        get "/",      to: Flash::Controllers::Home::Index.new
        post "/",     to: Flash::Controllers::Home::Index.new
        get "/print", to: Flash::Controllers::Home::Print.new
        get "/books", to: Flash::Controllers::Home::Books.new
        get "/map_redirect",   to: Flash::Controllers::Home::MapRedirect.new
        get "/each_redirect",  to: Flash::Controllers::Home::EachRedirect.new
        get "/map",            to: Flash::Controllers::Home::Map.new
        get "/each",           to: Flash::Controllers::Home::Each.new
        get "/disabled",       to: Flash::Controllers::Home::Disabled.new
      end

      @middleware = Rack::Builder.new do
        use Rack::Session::Cookie, secret: SecureRandom.hex(16)
        run routes
      end
    end

    def call(env)
      @middleware.call(env)
    end
  end
end

module Inheritance
  class Action < Hanami::Action
    before :log_base_action

    private

    def log_base_action(*, res)
      res[:base_action] = true
    end
  end

  class AuthenticatedAction < Action
    before :authenticate!

    private

    def authenticate!(*, res)
      res[:authenticated] = true
    end
  end

  module Controllers
    module Books
      class RestfulAction < AuthenticatedAction
        before :find_book
        after :render

        private

        def find_book(req, res)
          res[:book] = "book #{req.params[:id]}"
        end

        def render(*, res)
          res.body = res.exposures.keys
        end
      end

      class Show < RestfulAction
        def handle(*, res)
          res[:found] = true
        end
      end

      class Destroy < Show
        def handle(*, res)
          super
          res[:destroyed] = true
        end
      end
    end
  end

  class Application
    def initialize
      @routes = Hanami::Router.new do
        resources :books, only: %i[show destroy]
      end
    end

    def call(env)
      @routes.call(env)
    end
  end
end

class ContractActionBase < Hanami::Action
  def handle(request, response)
    if request.params.valid?
      response.status = 201
      response.body = JSON.generate(
        new_name: request.params[:book][:title].upcase
      )
    else
      response.body = {errors: request.params.errors.to_h}
      response.status = 302
    end
  end
end

class ContractAction < ContractActionBase
  contract do
    params do
      required(:birth_date).filled(:date)
      required(:book).schema do
        required(:title).filled(:str?)
      end
    end

    rule(:birth_date) do
      key.failure("you must be 18 years or older") if value < Date.today << (12 * 18)
    end
  end
end

class ExternalContract < Dry::Validation::Contract
  params do
    required(:birth_date).filled(:date)
    required(:book).schema do
      required(:title).filled(:str?)
    end
  end

  rule(:birth_date) do
    key.failure("you must be 18 years or older") if value < Date.today << (12 * 18)
  end
end

class ExternalContractAction < ContractActionBase
  contract ExternalContract
end

class DependencyContractAction < ContractActionBase
end

class WhitelistedUploadDslContractAction < Hanami::Action
  contract do
    params do
      required(:id).maybe(:integer)
      required(:upload).filled
    end
  end

  def handle(req, res)
    res.body = req.params.to_h.inspect
  end
end

class RawContractAction < Hanami::Action
  def handle(req, res)
    res.body = req.params.to_h.inspect
  end
end
