(in-package :cl-conllu)

(defun diff-sentences (p-sentence g-sentence evaluation-function confusion-table diff-table)
  
  (loop for p-token in (sentence-tokens p-sentence)
        for g-token in (sentence-tokens g-sentence) do

       (let ((p-value (funcall evaluation-function p-token p-sentence))
	     (g-value (funcall evaluation-function g-token g-sentence)))



	 (confusion-table-add-pair g-value p-value confusion-table)
	 (report-diff p-value g-value p-token g-token p-sentence g-sentence diff-table))))


(defun get-token-parent (token sent)
  (if (= (token-head token) 0)
      nil
      (token-parent token sent)))


(defun format-sentence-text (sentence &optional highlighted-tokens)
  (let ((ids (mapcar #'token-id highlighted-tokens)))
    (custom-sentence->text
     sentence
     :ignore-mtokens t
     :special-format-test
     #'(lambda (token)
	 (find (token-id token)
		ids))
     :special-format-function
     #'(lambda (string)
	 (format nil "<b>~a</b>" string)))))


(defun format-dependency (token sent)
  (if (= (token-head token) 0)
      (format nil "~a (~a)" (token-deprel token) (token-form token))
      (format nil "~a (~a , ~a)" (token-deprel token) (token-form token) (token-form (token-parent token sent)))))

(defun format-dependency-pair (p-token g-token p-sentence g-sentence)
  (format nil "~a ~a" (html-set-font-color (format-dependency g-token g-sentence) "blue")
	              (html-set-font-color (format-dependency p-token p-sentence) "red")))


(defun html-set-font-color (text color)
  (format nil "<font color=\"~a\"> ~a </font>" color text))


(defun html-set-bold (text)
  (format nil "<b>~a</b>" text))


(defun html-make-info-line (topic line)
  (format nil "<p>~a ~a</p>"
	  (html-set-bold (format nil "~a:" topic))
	  line))


(defun format-log-message (p-value g-value p-token g-token p-sentence g-sentence diff-table)
  (format nil "~{~a ~}<br>" (list (html-make-info-line "Id" (sentence-id g-sentence))
    (html-make-info-line "Text" (format-sentence-text g-sentence (remove nil (list g-token (get-token-parent g-token g-sentence)))))
    (html-make-info-line "Dep" (format-dependency-pair p-token g-token p-sentence g-sentence)))))


(defun format-header (p-value g-value)
  (format nil "<h3>(~a ~a)</h3>" (html-set-font-color g-value "blue") (html-set-font-color p-value "red")))

(defun report-diff (p-value g-value p-token g-token p-sentence g-sentence diff-table)
  ; conflict found
  (when (not (string= g-value p-value))
    (let ((header (format-header p-value g-value))
	  (formatted-log (format-log-message p-value g-value p-token g-token p-sentence g-sentence diff-table)))
      
      (add-diff-log p-value g-value formatted-log diff-table))))


(defun add-diff-log (p-val g-val log diff-table)
  (when (not (gethash g-val diff-table))
    (setf (gethash g-val diff-table) (make-hash-table :test 'equal)))

    (if (not (gethash p-val (gethash g-val diff-table)))
      (setf (gethash p-val (gethash g-val diff-table)) (list log))
      (push log (cdr (gethash p-val (gethash g-val diff-table))))))


(defun format-file-name (p-value g-value)
  (format nil "/~a~a.html" g-value p-value))

;;;;;;;;;;;;;;;;;;;;;;;;;

(defun write-diffs-to-files(diff-table diffs-path)
  (loop for g-value being the hash-keys in diff-table do
       (loop for p-value being the hash-keys in (gethash g-value diff-table) do
	    (let ((filename (concatenate  'string diffs-path  (format-file-name p-value g-value))))
	      
	    (with-open-file (file filename
				  :direction :output
				  :if-exists :append
				  :if-does-not-exist :create)

	      (when (= (file-length file) 0)
		   (write-charset file)
		   (write-style-css file))
	      (loop for log in (gethash p-value (gethash g-value diff-table)) do
		   (write-line log file))
	      
	      (setf (gethash p-value (gethash g-value diff-table)) nil))))))


(defun confusion-table-add-column (confusion-table new-column)
  (print new-column)
  ; Add new column
  (setf (gethash new-column confusion-table) (make-hash-table :test 'equal))

  ; Adds the cell value for the new column to each row
  (loop for row being the hash-values of confusion-table do
       (setf (gethash new-column row) 0))

  ; Adds value for every cell of the new column
  (loop for key being the hash-keys of confusion-table do
       (setf (gethash key (gethash new-column confusion-table)) 0)))


(defun confusion-table-add-pair (g-value p-value confusion-table)

  ; TODO - Simplify duplicate code

  ;(print (alexandria:hash-table-keys confusion-table))

  (when (not (gethash p-value confusion-table))
    (confusion-table-add-column confusion-table p-value))

  (when (not (gethash g-value confusion-table))
    (confusion-table-add-column confusion-table g-value))

  ;(print (gethash p-value (gethash g-value confusion-table)))
  (incf  (gethash p-value (gethash g-value confusion-table))))


(defun report-confusion-table (path golden-files prediction-files evaluation-function &optional (batch-write 50) (diffs-path "diffs"))

  (let ((confusion-table (make-hash-table :test 'equal))
	(diff-table (make-hash-table :test 'equal))
	(counter 0))
    
    (with-open-file (report path
			    :direction :output
			    :if-exists :supersede
			    :if-does-not-exist :create)
      
      (loop for p-file in prediction-files
	    for g-file in golden-files do
	   
	   (assert (string= (file-namestring p-file) (file-namestring g-file)) (p-file g-file) "invalid match of filenames")
	   
       (loop for p-sentence in (read-file p-file)
	     for g-sentence in (read-file g-file) do
	    (diff-sentences p-sentence g-sentence evaluation-function confusion-table diff-table))


	   (print counter)
	   (incf counter)

	   (when (=(rem counter batch-write) 0)
	     (write-diffs-to-files diff-table diffs-path)))
      
      (write-charset report)
      (write-style-css report)
      (write-confusion-table confusion-table report diffs-path)

      (write-diffs-to-files diff-table diffs-path)
      )))


(defun confusion-table-access-cell-counter (row col table)
  "Returns the value of the confusion table defined by the row and col"
  (gethash row (gethash col table)))


(defun confusion-table-rows (table)
  " Returns the rows of the confusion table "
  (let ((rows (list (alexandria:flatten (append '("") (alexandria:hash-table-keys table)))))
	(columns (alexandria:hash-table-keys table)))
    
    (loop for line in columns do
	 (let ((row (list line)))
	   (loop for column in columns do
		(append-element (write-to-string (confusion-table-access-cell-counter line column table)) row))
	   (append-element row rows)))
    rows))


(defun write-charset (stream)
  (write-line "<meta charset=\"UTF-8\">" stream))


(defun write-style-css (stream)
  (write-line "<style>
table, th, td {border: 1px solid black;border-collapse: collapse;padding: 5px;}
th, td {text-align: center;}
tr:first-child {color:blue; font-weight: bold;}
td:first-child { color:red; font-weight: bold;}
p {margin:0px;}
html * {font-family: Helvetica;}

table {
  overflow: hidden;
}

tr:hover {
  background-color: #ffa;
}

td, th {
  position: relative;
}
td:hover::after,
th:hover::after {
  content: \"\";
  position: absolute;
  background-color: #ffa;
  left: 0;
  top: -5000px;
  height: 10000px;
  width: 100%;
  z-index: -1;
}
</style>
" stream))

(defun write-confusion-tabsle (confusion-table stream)
  (let ((width 10)
	(data (confusion-table-rows confusion-table)))
    (write-line (format nil "<table> ~{ <tr> ~{ <td> ~{~Vd~} </td> ~} </tr> ~% ~} </table>"
	  (mapcar #'(lambda (r) (mapcar #'(lambda (v) (list width v)) r)) data)) stream)))

(defun format-cell-html (val &optional color)
  (if color
    (format nil "<td  style=\"background-color:~a;\">~a</td>" color val)
    (format nil "<td >~a</td>" val)))

(defun format-row-html (val)
  (format nil "<tr>~a</tr>" val))

(defun format-table-html (val)
  (format nil "<table>~a</table>" val))

(defun format-link-html (val href )
    (format nil "<a href=\"~a\">~a</a>" href val))

(defun write-confusion-table (confusion-table stream diffs-path &optional (sort nil) sort-function )
  (write-line "<table>" stream)
  (let* ((column-names (alexandria:hash-table-keys confusion-table)))

    (when sort
      (funcall sort-function column-names))
    
    
					; write the header
    (write-line "<tr>" stream)
    (mapc (lambda(x) (write-line (format-cell-html x) stream)) (append '("") column-names))
    (write-line "</tr>" stream)
    
    (loop for row-name in column-names do
	 (write-line "<tr>" stream)
	 (loop for column-name in column-names for i from 0 do
	      (let ((value (confusion-table-access-cell-counter row-name column-name confusion-table))
		    (filename (concatenate 'string diffs-path (format-file-name row-name column-name))))
		    
		   ;((filename (concatenate 'string diffs-path (format-file-name row-name column-name)))))
		    

		(when (= i 0)
		  (print row-name)
		  (write-line (format-cell-html row-name) stream))
		
		(if (and (not(= value 0)) (not (string= row-name column-name)))
		    (write-line (format-cell-html (format-link-html value filename)) stream)
		    (if (string= row-name column-name)
			(write-line (format-cell-html value) stream)
			(write-line (format-cell-html value) stream)))))
		
		
	 (write-line "</tr>" stream)))
  (write-line "</table>" stream))


  

(defun custom-sentence->text (sentence &key (ignore-mtokens nil) (special-format-test #'null special-format-test-supplied-p) (special-format-function #'identity special-format-function-supplied-p))
  (assert (or (and special-format-test-supplied-p
		   special-format-function-supplied-p)
	      (and (not special-format-test-supplied-p)
		   (not special-format-function-supplied-p)))
	  (special-format-test
	   special-format-function)
	  "If a special format is intended, then both
	  SPECIAL-FORMAT-TEST and SPECIAL-FORMAT-FUNCTION should be
	  specified!")
  (assert (functionp special-format-test))
  (assert (functionp special-format-function))
  (labels ((forma (obj lst)
	     (let ((obj-form
		    (if (funcall special-format-test obj)
			(funcall special-format-function (slot-value obj 'form))
			(slot-value obj 'form))))
	       (if (search "SpaceAfter=No" (slot-value obj 'misc))
		   (cons obj-form lst)
		   (cons " " (cons obj-form lst)))))
	   (aux (tokens mtokens ignore response)
	     (cond 
	       ((and (null tokens) (null mtokens))
		(if (equal " " (car response))
		    (reverse (cdr response))
		    (reverse response)))

	       ((and ignore (< (token-id (car tokens)) ignore))
		(aux (cdr tokens) mtokens ignore response))
	       ((and ignore (equal (token-id (car tokens)) ignore))
		(aux (cdr tokens) mtokens nil response))
      
	       ((and mtokens (<= (mtoken-start (car mtokens)) (token-id (car tokens))))
		(aux tokens (cdr mtokens)
				   (mtoken-end (car mtokens))
				   (forma (car mtokens) response)))
	       (t
		(aux (cdr tokens) mtokens ignore (forma (car tokens) response))))))
    (format nil "~{~a~}" (aux (sentence-tokens sentence)
			      (if ignore-mtokens
				  nil
				  (sentence-mtokens sentence))
			      nil nil))))