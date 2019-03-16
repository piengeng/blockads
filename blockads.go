package main

import (
	"bufio"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"time"
)

const userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:65.0) Gecko/20100101 Firefox/65.0"

func main() {
	urls := sourcing("./config/source_hosts") // step 1 sourcing hosts
	downloading(urls)                         // step 2 downloading concurrently
	processing("./cache/*.host")              // step 3 processing
	restarting()                              // step 4 copy & restart
}

func sourcing(source string) []string {
	urls := make([]string, 0)
	file, err := os.Open(source)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		match, _ := regexp.MatchString(`^\s*#`, line)
		if !match && line != "" {
			urls = append(urls, line)
		}
	}
	return urls
}

func downloading(urls []string) {
	chFailedUrls := make(chan string)
	chPassedUrls := make(chan string)
	chIsFinished := make(chan bool)

	for i, url := range urls {
		go fetchUrl(i, url, chFailedUrls, chPassedUrls, chIsFinished)
	}

	failedUrls := make([]string, 0)
	passedUrls := make([]string, 0)
	for i := 0; i < len(urls); {
		select {
		case url := <-chFailedUrls:
			failedUrls = append(failedUrls, url)
		case url := <-chPassedUrls:
			passedUrls = append(passedUrls, url)
		case <-chIsFinished:
			i++
		}
	}

	fmt.Println("Passed: ", passedUrls)
	fmt.Println("Failed: ", failedUrls)
}

func processing(glob string) {
	files, err := filepath.Glob(glob)
	check(err)
	// fmt.Printf("%#v", files)
	lines := make([]string, 0)

	// cleaning & merging
	for _, file := range files {
		lines = append(lines, cleaning(file)...)
		// break // debug only
	}
	initially := len(lines)
	fmt.Println("pass1:", initially)
	lines = unique(lines)
	fmt.Println("pass2:", len(lines))

	// find shortest url by tld
	// sort.Strings(lines)                     // debug only
	// lines2file(lines, "./cache/lines.test") // debug only

	for i, line := range lines {
		lines[i] = reverse(line)
	}
	sort.Strings(lines)
	// lines2file(lines, "./cache/lines.test.1") // debug only

	// marking approach, mark first then remove
	prevLine := ""
	for i := 0; i < len(lines); i++ {
		currLine := lines[i]
		if strings.HasPrefix(lines[i], prevLine+".") {
			lines[i] = "#" + lines[i]
		} else {
			prevLine = currLine
		}
	}
	// lines2file(lines, "./cache/lines.test.2") // debug only
	preFinal := removeMarked(lines)

	// manual excludes first, remove from preFinal
	excludes := sourcing("./config/manual_excludes")
	for i, line := range preFinal {
		for _, exclude := range excludes {
			target := reverse(exclude)
			if strings.HasPrefix(line, target) {
				preFinal[i] = "#" + preFinal[i]
			}
		}
	}
	excluded := removeMarked(preFinal)
	// lines2file(excluded, "./cache/lines.test.3") // debug only

	// manual includes last, so overwrites excludes
	includes := sourcing("./config/manual_includes")
	for _, include := range includes {
		excluded = append(excluded, reverse(include))
	}
	included := unique(excluded)

	prepend := ""
	if runtime.GOOS != "windows" {
		prepend = "/etc/bind/"
	}
	for i, line := range included {
		included[i] = "zone \"" + reverse(line) + "\" {type master;notify no;file \"" + prepend + "db.empty\";};"
	}
	// sort.Strings(preFinal)	// debug only
	lines2file(included, "./cache/named.conf.adblock")
	finally := len(included)
	fmt.Println("pass3:", finally)
	fmt.Println("final:", initially, "->", finally, percentage(initially, finally)+"%")
}

func restarting() {
	input, err := ioutil.ReadFile("./cache/named.conf.adblock")
	check(err)

	file := ""
	if runtime.GOOS != "windows" {
		file = "/etc/bind/" + "named.conf.adblock"
	} else {
		file = "C:/named/etc/" + "named.conf.adblock"
	}

	err = ioutil.WriteFile(file, input, 0644)
	check(err)

	if runtime.GOOS != "windows" {
		_, err := exec.Command("bash", "-c", "systemctl restart bind9").Output()
		check(err)
	}
}

func cleaning(filepath string) []string {
	lines := make([]string, 0)
	rFile, err := os.Open(filepath)
	check(err)
	defer rFile.Close()

	re1 := regexp.MustCompile(`\s*#.*$`)                    // remove comments
	re2 := regexp.MustCompile(`((127|0)\.0\.0\.(1|0))|::1`) // remove ip
	re3 := regexp.MustCompile(`^\s*localhost\s*$`)          // remove localhost
	// re4 := regexp.MustCompile(`^\s+|\s+$`)                  // remove spaces

	scanner := bufio.NewScanner(rFile)
	for scanner.Scan() {
		line := scanner.Text()
		line = strings.ToLower(line)
		line = re1.ReplaceAllString(line, "")
		line = re2.ReplaceAllString(line, "")
		line = re3.ReplaceAllString(line, "")
		line = strings.TrimSpace(line)

		spaced, _ := regexp.MatchString(`.+\s+.+`, line)
		if line != "" && !spaced {
			lines = append(lines, line)
			// } else {
			// 	fmt.Println(line)
		}
	}
	// lines2file(lines, filepath+".test.1") // debug only
	return lines
}

func removeMarked(lines []string) []string {
	data := []string{}
	for _, line := range lines {
		if !strings.HasPrefix(line, "#") {
			data = append(data, line)
		}
	}
	return data
}

func reverse(s string) string {
	runes := []rune(s)
	for i, j := 0, len(runes)-1; i < j; i, j = i+1, j-1 {
		runes[i], runes[j] = runes[j], runes[i]
	}
	return string(runes)
}

func unique(s []string) []string {
	m := make(map[string]bool)
	for _, item := range s {
		if _, ok := m[item]; ok {
			// fmt.Println("duplicate:", item)
		} else {
			m[item] = true
		}
	}

	var result []string
	for item, _ := range m {
		result = append(result, item)
	}
	return result
}

func fetchUrl(i int, url string, chFailedUrls chan string, chPassedUrls chan string, chIsFinished chan bool) {
	client := &http.Client{
		Timeout: time.Second * 10,
	}
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("User-Agent", userAgent)
	resp, err := client.Do(req)

	defer func() {
		chIsFinished <- true
	}()

	if err != nil || resp.StatusCode != 200 {
		chFailedUrls <- url
		return
	} else {
		chPassedUrls <- url
	}

	body, _ := ioutil.ReadAll(resp.Body)
	filename := fmt.Sprintf("./cache/%d.host", i)
	errFile := ioutil.WriteFile(filename, body, 0644)
	check(errFile)
}

func lines2file(lines []string, path string) {
	wFile, err := os.Create(path)
	check(err)
	defer wFile.Close()
	writer := bufio.NewWriter(wFile)
	for _, line := range lines {
		fmt.Fprintln(writer, line)
	}
	writer.Flush()
}

func percentage(o, n int) (delta string) {
	diff := float64(o) - float64(n)
	delta = fmt.Sprintf("%.2f", diff/float64(o)*100)
	return
}

func check(e error) {
	if e != nil {
		panic(e)
	}
}
