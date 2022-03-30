/*   
  Horstine1337@safe-mail.net 30. Mar. 2022
  To compile download the V compiler from https://vlang.io/
  Then use in console
  $ v ptdownloader.v

  Boost Software License - Version 1.0 - August 17th, 2003

  Permission is hereby granted, free of charge, to any person or organization
  obtaining a copy of the software and accompanying documentation covered by
  this license (the "Software") to use, reproduce, display, distribute,
  execute, and transmit the Software, and to prepare derivative works of the
  Software, and to permit third-parties to whom the Software is furnished to
  do so, all subject to the following:

  The copyright notices in the Software and this entire statement, including
  the above license grant, this restriction and the following disclaimer,
  must be included in all copies of the Software, in whole or in part, and
  all derivative works of the Software, unless such copies or derivative
  works are solely in the form of machine-executable object code generated by
  a source language processor.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
  SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
  FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.
*/

import os
import net.http
import regex
import strings
import net.html


// Find last index of a single character in a string array
fn last_index_of(str string, search_for_char string) int {
	assert(search_for_char.len == 1)
	assert(str.len > 0)

	mut cur_last_index := -1
	for index, c in str {
		if c.ascii_str() == search_for_char {
			cur_last_index = index
		}
	}
	return cur_last_index
}


// Didn't find anything but [array] in [array] and don't want to convert big html strings
// This is a standard string.contains(string) method
fn contains(str string, search_for_str string) bool {
	assert(str.len > 0)
	assert(search_for_str.len > 0)
	assert(str.len >= search_for_str.len)

	for i in 0..str.len {
		if str[i] == search_for_str[0] {
			//break early if rest of str is shorter than string to search for
			if str.len-i < search_for_str.len {
				return false
			}
			mut not_equal := false
			for j in 0..search_for_str.len {
				if str[i+j] != search_for_str[j] {
					not_equal = true
					break
				}
			}
			if !not_equal {
				return true
			}
		}
	}
	return false
}


// Because regex doesn't seem to work quite yet and I don't want to involve C 
// or some non standard package, this will do for now
// This looks for certain sub strings in the given html to find .mp3 URLs
fn find_all_mp3_links(h string) []string {
	assert(h.len > 0)
	
	mut ret := []string{}

/* 	<a href="https://feeds.soundcloud.com/stream/1blabla.mp3" 
	target="_blank"	title="Download">
	<i class="icon-cloud-download" aria-hidden="true"></i> Download</a> */
	
	for i in 0..h.len {
		//if cursor is on '"http'
		if h.len > i+4
			&& h[i].ascii_str() == '"'
			&& h[i+1].ascii_str() == 'h'
			&& h[i+2].ascii_str() == 't'
			&& h[i+3].ascii_str() == 't'
			&& h[i+4].ascii_str() == 'p' {

			//just having some fun here
			mut j := i+1 // we don't want the '"' in the final link URL
			mut found := false
			mut buf := strings.new_builder(0)
			
			for !found || j > h.len {
				if h.len > j+4
					&& h[j].ascii_str() == '.'
					&& h[j+1].ascii_str() == 'm'
					&& h[j+2].ascii_str() == 'p'
					&& h[j+3].ascii_str() == '3'
					&& h[j+4].ascii_str() == '"' {

						buf.write_byte(h[j])
						buf.write_byte(h[j+1])
						buf.write_byte(h[j+2])
						buf.write_byte(h[j+3])
						found = true
					} else {
						if h[j].ascii_str() == '"' {
							// if there is an '"' between http and .mp3,
							// thats not the link we are looking for
							break
						}

						buf.write_byte(h[j])
						j++
					}
			}
			if found {
				ret << buf.str()			
			}
		}
	}

	return ret
}


// Download all files from given URLs to given directory
fn download_links(links []string, path_to string){
  if path_to == "" {
    println("No download directory provided.")
    return
  }

  if links.len == 0 {
    println("No download links found.")
    return
  }

  for link in links {
    index := last_index_of(link, '/')
    // if empty string or no '/' was found, ignore the current link
    if index == -1 || link == "" {
			continue
		}
  	save_to := link[index+1 .. link.len]
    // if the file already exists, ignore
    if os.exists(path_to + save_to) {
			continue
		}
    //download and save to given directory
    println("Downloading " + link + " to " + path_to + save_to)
		if !os.is_dir(path_to) {
			os.mkdir_all(path_to) or { 
				println(err)
				continue
			}
		}
    http.download_file(link, path_to + save_to) or {continue}
  }
}

// FixMe: replace find_all_mp3_links(html) with regex, once it's working
// Iterate over all pages for current podcast until "No episodes found".
// Then parse all URLs containing ".mp3" from the downloaded html.
fn find_all_download_links_by_regex(podcast_url string) []string {
  mut done := false
  mut cur_page_number := 1
  mut ret := []string{}
	// Look ma, magic!
	mp3_reg_query := 'http?s:[^"]*\\\\.mp3'
  mut mp3_reg := regex.regex_opt(mp3_reg_query) or { panic(err) }

  for !done {
	  url_for_current_page := "$podcast_url?page=$cur_page_number&append=false&sort=latest&q="
    cur_page_number++

    println("Searching download links on " + url_for_current_page)
    tmp_received_html := http.get(url_for_current_page) or {continue}.text
    if contains(tmp_received_html, "<p>No episodes found.</p>") {
      done = true
    }

		found_mp3_links_array := find_all_mp3_links(tmp_received_html)
		ret << found_mp3_links_array
  }

  return ret
}

fn find_all_download_links_by_dom(podcast_url string) []string {
	mut done := false
  mut cur_page_number := 1
  mut ret := []string{}

	for !done {
	  url_for_current_page := "$podcast_url?page=$cur_page_number&append=false&sort=latest&q="
    cur_page_number++

    println("Searching download links on " + url_for_current_page)
    tmp_received_html := http.get(url_for_current_page) or {continue}.text
    if contains(tmp_received_html, "<p>No episodes found.</p>") {
      done = true
    }

    //put some tag around the downloaded html to fix an issue with dom.d
		//just copy&pasted from the D implementation; didn't even test without the extra tags
		mut document := html.parse('<div>' + tmp_received_html + '</div>')
		download_link_tags := document.get_tag_by_attribute_value("title", "Download")

		for tag in download_link_tags {
			ret << tag.attributes['href']		
		}
  }

  return ret
}


fn write_help_message() {
    println(r"Please specify the podcast URL like 
./ptdownloader https://podtail.com/podcast/NAME/

If you want to store the files in a different directory than the working dir,
./ptdownloader https://podtail.com/podcast/NAME/ ./download/directory/

Alternatively you can set the download lookup to dom,
which will download any href where html attribute title='Download'
./ptdownloader dom https://podtail.com/podcast/NAME/ ./download/directory/

The detault will look for URLs ending with '.mp3'.")
}


fn main() {
  mut use_regex := true
  mut podcast_url := ""
  mut links := []string{}
  mut dl_dir := "./"

	mut args := os.args.clone()[1..os.args.len] // get rid of name 
	//prepare arguments
  if args.len == 0 {
    write_help_message()
    return
  }

  if args[0] == "dom" {
    use_regex = false
    args = args[1..args.len]
  }

  if args.len != 0 {
    podcast_url = args[0]
    args = args[1..args.len]
  }else {
    write_help_message()
  }

  if args.len != 0 {
    dl_dir = args[0]
    args = args[1..args.len]
  }

  //do the work
  if use_regex {
    links = find_all_download_links_by_regex(podcast_url)
	}
  else {
    links = find_all_download_links_by_dom(podcast_url)
	}
  download_links(links, dl_dir)
}