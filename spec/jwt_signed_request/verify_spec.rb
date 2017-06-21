require 'jwt_signed_request'
require 'rack'

module JWTSignedRequest
  RSpec.describe Verify do
    let(:request_env) do
      {
        "SERVER_SOFTWARE"=>"thin 1.4.1 codename Chromeo",
        "SERVER_NAME"=>"localhost",
        "rack.input"=>StringIO.new("data=body"),
        "rack.version"=>[1, 0],
        "rack.errors"=>"",
        "rack.multithread"=>false,
        "rack.multiprocess"=>false,
        "rack.run_once"=>false,
        "REQUEST_METHOD"=>"POST",
        "REQUEST_PATH"=>"/api/endpoint",
        "PATH_INFO"=>"/api/endpoint",
        "REQUEST_URI"=>"/api/endpoint",
        "CONTENT_TYPE"=>"application/json",
        "HTTP_VERSION"=>"HTTP/1.1",
        "HTTP_HOST"=>"localhost:8080",
        "HTTP_CONNECTION"=>"keep-alive",
        "HTTP_ACCEPT"=>"*/*",
        "HTTP_USER_AGENT"=>
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_4) AppleWebKit/536.11 (KHTML, like Gecko) Chrome/20.0.1132.47 Safari/536.11",
        "HTTP_ACCEPT_ENCODING"=>"gzip,deflate,sdch",
        "HTTP_ACCEPT_LANGUAGE"=>"en-US,en;q=0.8",
        "HTTP_ACCEPT_CHARSET"=>"ISO-8859-1,utf-8;q=0.7,*;q=0.3",
        "HTTP_COOKIE"=> "_gauges_unique_year=1;  _gauges_unique_month=1",
        "GATEWAY_INTERFACE"=>"CGI/1.2",
        "SERVER_PORT"=>"8080",
        "QUERY_STRING"=>"",
        "SERVER_PROTOCOL"=>"HTTP/1.1",
        "rack.url_scheme"=>"http",
        "SCRIPT_NAME"=>"",
        "REMOTE_ADDR"=>"127.0.0.1",
      }
    end

    let(:request) { Rack::Request.new(request_env) }
    let(:secret_key) { 'secret' }
    let(:jwt_token) { 'potato' }

    let(:method) { request_env['REQUEST_METHOD'] }
    let(:path) { request_env['REQUEST_PATH'] }
    let(:body) { request_env['rack.input'] }
    let(:body_sha) { Digest::SHA256.hexdigest(body.string) }
    let(:headers) { JSON.dump('content-type' => 'application/json') }

    subject(:verify_request) do
      Verify.call(request: request, secret_key: secret_key)
    end

    context 'when request has no Authorization header' do
      it 'raises a MissingAuthorizationHeaderError' do
        expect{ verify_request }.to raise_error(JWTSignedRequest::MissingAuthorizationHeaderError)
      end
    end

    context 'when there is an Authorization header set' do
      let(:request) do
        Rack::Request.new(request_env.merge({'HTTP_AUTHORIZATION' => jwt_token}))
      end

      let(:claims) do
        [{
          'method' => method,
          'path' => path,
          'body_sha' => body_sha,
          'headers' => headers,
        }]
      end

      before do
        allow(JWT).to receive(:decode).and_return(claims)
      end

      context 'and the request matches the JWT claims' do
        it 'does not raise any errors' do
          expect{ verify_request }.not_to raise_error
        end
      end

      context 'and the request method is different' do
        let(:method) { 'GET' }

        it 'raises a RequestVerificationFailedError' do
          expect{ verify_request }.to raise_error(JWTSignedRequest::RequestVerificationFailedError)
        end
      end

      context 'and there is no request method in the claims' do
        let(:method) { nil }

        it 'raises a RequestVerificationFailedError' do
          expect{ verify_request }.to raise_error(JWTSignedRequest::RequestVerificationFailedError)
        end
      end

      context 'and the request path is different' do
        let(:path) { '/api/different/endpoint'}

        it 'raises a RequestVerificationFailedError' do
          expect{ verify_request }.to raise_error(JWTSignedRequest::RequestVerificationFailedError)
        end
      end

      context 'and the body is different' do
        let(:body_sha) { '1ddfd12592f1090bb0f18a744abe97d07c7adacad3d3a27a9bfa927ff07f7b3c' }

        it 'raises a RequestVerificationFailedError' do
          expect{ verify_request }.to raise_error(JWTSignedRequest::RequestVerificationFailedError)
        end
      end

      context 'and the request headers are different' do
        let(:headers) { JSON.dump('content-type' => 'application/xml') }

        it 'raises a RequestVerificationFailedError' do
          expect{ verify_request }.to raise_error(JWTSignedRequest::RequestVerificationFailedError)
        end
      end

      context 'and there are no headers in the claims' do
        let(:headers) { nil }

        it 'does not raise an error' do
          expect { verify_request }.to_not raise_error
        end
      end

      context 'and the headers are invalid JSON in the claim' do
        let(:headers) { 'invalid' }

        it 'does not raise an error' do
          expect { verify_request }.to_not raise_error
        end
      end

      context 'and expiry leeway is provided' do
        subject(:verify_request) do
          Verify.call(request: request, secret_key: secret_key, leeway: 123)
        end

        it 'uses the specified leeway' do
          verify_request
          expect(JWT).to have_received(:decode).with(jwt_token, secret_key, true, leeway: 123)
        end
      end

      context 'and expiry leeway is not provided' do
        subject(:verify_request) do
          Verify.call(request: request, secret_key: secret_key)
        end

        it 'does not pass the leeway with options' do
          verify_request
          expect(JWT).to have_received(:decode).with(jwt_token, secret_key, true, {})
        end
      end

      it 'allows the body to be read' do
        verify_request
        expect(request.body.read).to eq 'data=body'
      end
    end
  end
end