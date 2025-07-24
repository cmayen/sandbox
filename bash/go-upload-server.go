package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
)


// sudo docker exec -it new-image-name-localtest bash


const listenPort string = "8181"



func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
    // Prepare JSON response
    response := map[string]string{
      "status": fmt.Sprintf("%d", http.StatusMethodNotAllowed),
      "message":  "Method not allowed",
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
		return
	}

	// Parse the multipart form data
	err := r.ParseMultipartForm(10 << 20) // 10 MB limit for form data
	if err != nil {
    // Prepare JSON response
    response := map[string]string{
      "status": fmt.Sprintf("%d", http.StatusBadRequest),
      "message":  fmt.Sprintf("Error parsing multipart form: %v", err),
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
		return
	}

	// Get form fields
	host := r.FormValue("host")
	date := r.FormValue("date")

	// Get the "log" file
	file, handler, err := r.FormFile("log")
	if err != nil {
    // Prepare JSON response
    response := map[string]string{
      "status": fmt.Sprintf("%d", http.StatusInternalServerError),
      "message":  fmt.Sprintf("Error retrieving file 'log': %v", err),
      "filename": handler.Filename,
      "host":     host,
      "date":     date,
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
		return
	}
	defer file.Close()

	// Create the directory if it doesn't exist
	uploadDir := "./uploads" // Define your upload directory
	if _, err := os.Stat(uploadDir); os.IsNotExist(err) {
		err = os.Mkdir(uploadDir, 0755)
		if err != nil {
      // Prepare JSON response
      response := map[string]string{
        "status": fmt.Sprintf("%d", http.StatusInternalServerError),
        "message":  fmt.Sprintf("Error creating upload directory: %v", err),
        "filename": handler.Filename,
        "host":     host,
        "date":     date,
      }
      w.Header().Set("Content-Type", "application/json")
      json.NewEncoder(w).Encode(response)
			return
		}
	}

	// Create a new file on the filesystem to save the uploaded content
	dstPath := filepath.Join(uploadDir, handler.Filename)
	dst, err := os.Create(dstPath)
	if err != nil {
    // Prepare JSON response
    response := map[string]string{
      "status": fmt.Sprintf("%d", http.StatusInternalServerError),
      "message":  fmt.Sprintf("Error creating destination file: %v", err),
      "filename": handler.Filename,
      "host":     host,
      "date":     date,
      "filepath": dstPath,
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
		return
	}
	defer dst.Close()

	// Copy the uploaded file content to the destination file
  _, err = io.Copy(dst, file)
 	if err != nil {
    // Prepare JSON response
    response := map[string]string{
      "status": fmt.Sprintf("%d", http.StatusInternalServerError),
      "message":  fmt.Sprintf("Error copying file content: %v", err),
      "filename": handler.Filename,
      "host":     host,
      "date":     date,
      "filepath": dstPath,
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
		return
	}

	// Set permissions on the destination file
  // This will be used to signal that the file is ready for the parser
  // to take over. 

  //root@42e3692282f0:/uploads# find tuf--2025-07-18.report.txt -type f -perm 0400
  //tuf--2025-07-18.report.txt

	err = os.Chmod(dst, 0400)
	if err != nil {
    // Prepare JSON response
    response := map[string]string{
      "status": fmt.Sprintf("%d", http.StatusInternalServerError),
      "message":  fmt.Sprintf("Error setting file permission: %v", err),
      "filename": handler.Filename,
      "host":     host,
      "date":     date,
      "filepath": dstPath,
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
    return
	}





	// Prepare JSON response
	response := map[string]string{
    "status": "201",
		"message":  "File uploaded successfully",
		"filename": handler.Filename,
		"host":     host,
		"date":     date,
		"filepath": dstPath,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)

  // todo : use go func to call to script that will handle parsing
  //        sqlite database population, and the call to the 
  //        ai diagnostic tool api for the generated report
  // todo : this almost makes the setup for the dashboard to also
  //        be on this server. *shrugs* makes sense to me

}

func main() {
	http.HandleFunc("/uploadlog", uploadHandler)
	fmt.Println("Server listening on :"+listenPort)
	http.ListenAndServe(":"+listenPort, nil)
}
