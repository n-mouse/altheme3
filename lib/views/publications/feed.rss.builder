xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0" , 'xmlns' => 'http://backend.userland.com/rss2', 'xmlns:yandex' => 'http://news.yandex.ru' do
  xml.channel do
    xml.title "Доступ до правди"
    xml.description "Новини та історії сайту Доступ до правди"
    xml.link publications_url

    @publications.each do |pub|
      xml.item do
        xml.title pub.title
        xml.description pub.summary
        if pub.image_file_name
          xml.enclosure :url => "https://dostup.pravda.com.ua"+pub.image.url, :type=>"image/jpeg"
        end
        xml.pubDate pub.created_at.to_s(:rfc822)
        xml.link category_publication_url(pub.category, pub)
        xml.guid category_publication_url(pub.category, pub)
        xml.tag!("yandex:full-text") { xml.cdata!(pub.fulltext) }
      end
    end
  end
end

