# -*- coding: utf-8 -*-

Plugin.create :tweet_generator do
  require 'pstore'
  require 'mecab'
  require 'set'
  require 'pp'

  class Generator
    def initialize(knowledge = {})
      @knowledge = knowledge
      @m = MeCab::Tagger.new("-Owakati")
    end

    # 受信したテキストについてそれを学習します
    def add_data(str)
      ['START FLG','START FLG', *@m.parse(str).split(' '), 'STOP FLG'].each_cons(3) do |i, j, k|
        @knowledge[[i, j]] ||= Set.new
        @knowledge[[i, j]] << k
      end
    end

    # 学習データを返します
    def get_data()
      @knowledge
    end

    # 指定した文字数以下の適当な文字列を返します
    def generate(str_len = 140)
      if @knowledge.empty?
        activity :hour_signal, "学習データが存在しません"
      else
        100.times do
          str = gen_tweet
          return str if str.size <= str_len
        end
      end
      return ''
    end

    # 2次のマルコフ連鎖で文章を生成します
    def gen_tweet
      tweet = ['START FLG', 'START FLG']
      begin
        tweet << @knowledge[tweet[-2, 2]].to_a.sample
      end until tweet[-1] == 'STOP FLG'
      tweet[2..-2].join
    end
  end

  # 保存先の確保
  DATA = PStore.new(File.expand_path('~/.mikutter/knowledge.dat'))

  # データのロード
  DATA.transaction do |data|
    @generator = (data['knowledge'] ? Generator.new(data['knowledge']) : Generator.new())
  end

  # メッセージをポストしたらデータを追加
  on_posted do |service, messages|
    messages.each do |message|
      unless message.retweet?
        str = ''
        # 適当にアット，ハッシュタグ，リンクを削除
        message.to_show.split(/[ 　]/).each do |s|
          str += s + ' ' unless s =~ /([@#＃]|http).*/
        end
        @generator.add_data(str)
        DATA.transaction do |data|
          data['knowledge'] = @generator.get_data
        end
      end
    end
  end

  # コマンドの設定
  command(:tweet_generator,
            name: 'いい感じのそれらしい文字列を生成',
            condition: lambda{ |opt| true },
            visible: false,
            role: :postbox) do |opt|
      raw_postbox = Plugin.filtering(:gui_get_gtk_widget, opt.widget).first
      buffer = raw_postbox.widget_post.buffer
      text = @generator.generate(140 - buffer.get_text.size)
      last = buffer.selection_bounds[1]
      buffer.insert(last, text)
  end
end
