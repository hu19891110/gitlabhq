require 'spec_helper'

describe BlobHelper do
  include TreeHelper

  let(:blob_name) { 'test.lisp' }
  let(:no_context_content) { ":type \"assem\"))" }
  let(:blob_content) { "(make-pathname :defaults name\n#{no_context_content}" }
  let(:split_content) { blob_content.split("\n") }
  let(:multiline_content) do
    %q(
    def test(input):
      """This is line 1 of a multi-line comment.
      This is line 2.
      """
    )
  end

  describe '#highlight' do
    it 'returns plaintext for unknown lexer context' do
      result = helper.highlight(blob_name, no_context_content)
      expect(result).to eq(%[<pre class="code highlight"><code><span id="LC1" class="line" lang="">:type "assem"))</span></code></pre>])
    end

    it 'highlights single block' do
      expected = %Q[<pre class="code highlight"><code><span id="LC1" class="line" lang="common_lisp"><span class="p">(</span><span class="nb">make-pathname</span> <span class="ss">:defaults</span> <span class="nv">name</span></span>
<span id="LC2" class="line" lang="common_lisp"><span class="ss">:type</span> <span class="s">"assem"</span><span class="p">))</span></span></code></pre>]

      expect(helper.highlight(blob_name, blob_content)).to eq(expected)
    end

    it 'highlights multi-line comments' do
      result = helper.highlight(blob_name, multiline_content)
      html = Nokogiri::HTML(result)
      lines = html.search('.s')
      expect(lines.count).to eq(3)
      expect(lines[0].text).to eq('"""This is line 1 of a multi-line comment.')
      expect(lines[1].text).to eq('      This is line 2.')
      expect(lines[2].text).to eq('      """')
    end

    context 'diff highlighting' do
      let(:blob_name) { 'test.diff' }
      let(:blob_content) { "+aaa\n+bbb\n- ccc\n ddd\n"}
      let(:expected) do
        %q(<pre class="code highlight"><code><span id="LC1" class="line" lang="diff"><span class="gi">+aaa</span></span>
<span id="LC2" class="line" lang="diff"><span class="gi">+bbb</span></span>
<span id="LC3" class="line" lang="diff"><span class="gd">- ccc</span></span>
<span id="LC4" class="line" lang="diff"> ddd</span></code></pre>)
      end

      it 'highlights each line properly' do
        result = helper.highlight(blob_name, blob_content)
        expect(result).to eq(expected)
      end
    end
  end

  describe "#sanitize_svg_data" do
    let(:input_svg_path) { File.join(Rails.root, 'spec', 'fixtures', 'unsanitized.svg') }
    let(:data) { open(input_svg_path).read }
    let(:expected_svg_path) { File.join(Rails.root, 'spec', 'fixtures', 'sanitized.svg') }
    let(:expected) { open(expected_svg_path).read }

    it 'retains essential elements' do
      expect(sanitize_svg_data(data)).to eq(expected)
    end
  end

  describe "#edit_blob_link" do
    let(:namespace) { create(:namespace, name: 'gitlab' )}
    let(:project) { create(:project, :repository, namespace: namespace) }

    before do
      allow(self).to receive(:current_user).and_return(nil)
      allow(self).to receive(:can_collaborate_with_project?).and_return(true)
    end

    it 'verifies blob is text' do
      expect(helper).not_to receive(:blob_text_viewable?)

      button = edit_blob_link(project, 'refs/heads/master', 'README.md')

      expect(button).to start_with('<button')
    end

    it 'uses the passed blob instead retrieve from repository' do
      blob = project.repository.blob_at('refs/heads/master', 'README.md')

      expect(project.repository).not_to receive(:blob_at)

      edit_blob_link(project, 'refs/heads/master', 'README.md', blob: blob)
    end

    it 'returns a link with the proper route' do
      link = edit_blob_link(project, 'master', 'README.md')

      expect(Capybara.string(link).find_link('Edit')[:href]).to eq('/gitlab/gitlabhq/edit/master/README.md')
    end

    it 'returns a link with the passed link_opts on the expected route' do
      link = edit_blob_link(project, 'master', 'README.md', link_opts: { mr_id: 10 })

      expect(Capybara.string(link).find_link('Edit')[:href]).to eq('/gitlab/gitlabhq/edit/master/README.md?mr_id=10')
    end
  end

  context 'viewer related' do
    include FakeBlobHelpers

    let(:project) { build(:empty_project, lfs_enabled: true) }

    before do
      allow(Gitlab.config.lfs).to receive(:enabled).and_return(true)
    end

    let(:viewer_class) do
      Class.new(BlobViewer::Base) do
        self.max_size = 1.megabyte
        self.absolute_max_size = 5.megabytes
        self.type = :rich
        self.client_side = false
      end
    end

    let(:viewer) { viewer_class.new(blob) }
    let(:blob) { fake_blob }

    describe '#blob_render_error_reason' do
      context 'for error :too_large' do
        context 'when the blob size is larger than the absolute max size' do
          let(:blob) { fake_blob(size: 10.megabytes) }

          it 'returns an error message' do
            expect(helper.blob_render_error_reason(viewer)).to eq('it is larger than 5 MB')
          end
        end

        context 'when the blob size is larger than the max size' do
          let(:blob) { fake_blob(size: 2.megabytes) }

          it 'returns an error message' do
            expect(helper.blob_render_error_reason(viewer)).to eq('it is larger than 1 MB')
          end
        end
      end

      context 'for error :server_side_but_stored_in_lfs' do
        let(:blob) { fake_blob(lfs: true) }

        it 'returns an error message' do
          expect(helper.blob_render_error_reason(viewer)).to eq('it is stored in LFS')
        end
      end
    end

    describe '#blob_render_error_options' do
      before do
        assign(:project, project)
        assign(:id, File.join('master', blob.path))

        controller.params[:controller] = 'projects/blob'
        controller.params[:action] = 'show'
        controller.params[:namespace_id] = project.namespace.to_param
        controller.params[:project_id] = project.to_param
        controller.params[:id] = File.join('master', blob.path)
      end

      context 'for error :too_large' do
        context 'when the max size can be overridden' do
          let(:blob) { fake_blob(size: 2.megabytes) }

          it 'includes a "load it anyway" link' do
            expect(helper.blob_render_error_options(viewer)).to include(/load it anyway/)
          end
        end

        context 'when the max size cannot be overridden' do
          let(:blob) { fake_blob(size: 10.megabytes) }

          it 'does not include a "load it anyway" link' do
            expect(helper.blob_render_error_options(viewer)).not_to include(/load it anyway/)
          end
        end
      end

      context 'when the viewer is rich' do
        context 'the blob is rendered as text' do
          let(:blob) { fake_blob(path: 'file.md', lfs: true) }

          it 'includes a "view the source" link' do
            expect(helper.blob_render_error_options(viewer)).to include(/view the source/)
          end
        end

        context 'the blob is not rendered as text' do
          let(:blob) { fake_blob(path: 'file.pdf', binary: true, lfs: true) }

          it 'does not include a "view the source" link' do
            expect(helper.blob_render_error_options(viewer)).not_to include(/view the source/)
          end
        end
      end

      context 'when the viewer is not rich' do
        before do
          viewer_class.type = :simple
        end

        let(:blob) { fake_blob(path: 'file.md', lfs: true) }

        it 'does not include a "view the source" link' do
          expect(helper.blob_render_error_options(viewer)).not_to include(/view the source/)
        end
      end

      it 'includes a "download it" link' do
        expect(helper.blob_render_error_options(viewer)).to include(/download it/)
      end
    end
  end
end
