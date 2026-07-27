/* ============================================================================
   OULAD_ETL_and_Queries.sql
   Dự án: Hệ thống Cảnh báo Sớm & Theo dõi Mức độ Tương tác Học tập
   Mục đích: (1) Tạo schema quan hệ đúng theo ERD gốc của OULAD
             (2) Nạp 7 file CSV vào database
             (3) 7 câu truy vấn phân tích tạo insight cho SQL_Insights_Report.xlsx
   DBMS: SQLite 3 (chạy qua CLI: sqlite3 oulad.db < OULAD_ETL_and_Queries.sql)
   Tác giả: Business Analyst (dự án cá nhân) — 20/07/2026
   ============================================================================ */

PRAGMA foreign_keys = ON;

/* ============================================================================
   PHẦN 1 — DDL: TẠO SCHEMA QUAN HỆ (đúng theo ERD)
   Nhóm bảng:
     - Module Presentation : courses, assessments, vle
     - Student - demographics : studentInfo
     - Student - activities : studentRegistration, studentAssessment, studentVle
   ============================================================================ */

DROP TABLE IF EXISTS studentVle;
DROP TABLE IF EXISTS studentAssessment;
DROP TABLE IF EXISTS studentRegistration;
DROP TABLE IF EXISTS studentInfo;
DROP TABLE IF EXISTS vle;
DROP TABLE IF EXISTS assessments;
DROP TABLE IF EXISTS courses;

-- Bảng "gốc": danh mục các lượt mở lớp (module-presentation)
CREATE TABLE courses (
    code_module                 VARCHAR(45) NOT NULL,
    code_presentation            VARCHAR(45) NOT NULL,
    module_presentation_length   INT,
    PRIMARY KEY (code_module, code_presentation)
);

-- Danh sách bài đánh giá của từng lượt mở lớp
CREATE TABLE assessments (
    code_module        VARCHAR(45) NOT NULL,
    code_presentation  VARCHAR(45) NOT NULL,
    id_assessment      INT NOT NULL,
    assessment_type    VARCHAR(45),
    date               INT,
    weight             FLOAT,
    PRIMARY KEY (id_assessment),
    FOREIGN KEY (code_module, code_presentation)
        REFERENCES courses (code_module, code_presentation)
);

-- Danh mục học liệu điện tử (VLE) của từng lượt mở lớp
CREATE TABLE vle (
    id_site            INT NOT NULL,
    code_module        VARCHAR(45) NOT NULL,
    code_presentation  VARCHAR(45) NOT NULL,
    activity_type      VARCHAR(45),
    week_from          INT,
    week_to            INT,
    PRIMARY KEY (id_site),
    FOREIGN KEY (code_module, code_presentation)
        REFERENCES courses (code_module, code_presentation)
);

-- Thông tin nhân khẩu học & kết quả cuối cùng của sinh viên trong từng lượt mở lớp
CREATE TABLE studentInfo (
    code_module            VARCHAR(45) NOT NULL,
    code_presentation      VARCHAR(45) NOT NULL,
    id_student             INT NOT NULL,
    gender                 VARCHAR(3),
    region                 VARCHAR(45),
    highest_education      VARCHAR(45),
    imd_band               VARCHAR(16),
    age_band               VARCHAR(16),
    num_of_prev_attempts   INT,
    studied_credits        INT,
    disability             VARCHAR(3),
    final_result           VARCHAR(45),
    PRIMARY KEY (code_module, code_presentation, id_student),
    FOREIGN KEY (code_module, code_presentation)
        REFERENCES courses (code_module, code_presentation)
);

-- Thời điểm đăng ký / hủy đăng ký của sinh viên
CREATE TABLE studentRegistration (
    code_module          VARCHAR(45) NOT NULL,
    code_presentation     VARCHAR(45) NOT NULL,
    id_student            INT NOT NULL,
    date_registration      INT,
    date_unregistration    INT,
    PRIMARY KEY (code_module, code_presentation, id_student),
    FOREIGN KEY (code_module, code_presentation, id_student)
        REFERENCES studentInfo (code_module, code_presentation, id_student)
);

-- Kết quả nộp bài của sinh viên cho từng bài đánh giá
-- Lưu ý mô hình dữ liệu: id_student ở đây KHÔNG mang theo code_module/code_presentation
-- (một id_student có thể xuất hiện ở nhiều lượt mở lớp khác nhau trong studentInfo),
-- module/presentation của lượt nộp bài được suy ra gián tiếp qua assessments.id_assessment.
CREATE TABLE studentAssessment (
    id_assessment   INT NOT NULL,
    id_student      INT NOT NULL,
    date_submitted  INT,
    is_banked       TINYINT,
    score           FLOAT,
    PRIMARY KEY (id_assessment, id_student),
    FOREIGN KEY (id_assessment) REFERENCES assessments (id_assessment)
);

-- Nhật ký tương tác (clickstream) của sinh viên với học liệu điện tử — bảng lớn nhất
-- LƯU Ý QUAN TRỌNG: (code_module, code_presentation, id_student, id_site, date) KHÔNG
-- phải là khóa tự nhiên duy nhất trong dữ liệu thật — cùng một sinh viên/học liệu/ngày
-- có thể xuất hiện NHIỀU dòng riêng biệt (dữ liệu clickstream thô, chưa được nhà cung cấp
-- gộp trước khi xuất file: ví dụ sinh viên 28400 xem học liệu 546652 vào ngày -10 có tới
-- 3 dòng log riêng biệt với sum_click 1, 1, 8). Do đó bảng KHÔNG áp composite PRIMARY KEY
-- lên các cột nghiệp vụ (sẽ làm SQLite âm thầm loại bỏ ~2.2 triệu dòng hợp lệ khi nạp dữ
-- liệu). SQLite tự cấp phát ROWID nội bộ làm định danh duy nhất cho mỗi dòng, không cần
-- khai báo thêm cột — nhờ vậy số cột bảng vẫn khớp đúng 6 cột của file CSV khi .import.
CREATE TABLE studentVle (
    code_module        VARCHAR(45) NOT NULL,
    code_presentation  VARCHAR(45) NOT NULL,
    id_student         INT NOT NULL,
    id_site            INT NOT NULL,
    date               INT NOT NULL,
    sum_click          INT,
    FOREIGN KEY (code_module, code_presentation, id_student)
        REFERENCES studentInfo (code_module, code_presentation, id_student),
    FOREIGN KEY (id_site) REFERENCES vle (id_site)
);


/* ============================================================================
   PHẦN 2 — NẠP DỮ LIỆU TỪ 7 FILE CSV
   Thứ tự nạp phải đi từ bảng cha (courses) đến bảng con (studentVle) để không
   vi phạm ràng buộc khóa ngoại.
   Chạy bằng SQLite CLI (không chạy được nếu paste thẳng vào công cụ chỉ hỗ trợ
   SQL thuần, vì .mode/.import là lệnh riêng của sqlite3 shell, không phải SQL chuẩn).
   ============================================================================ */

.mode csv

.import --skip 1 courses.csv courses
.import --skip 1 assessments.csv assessments
.import --skip 1 vle.csv vle
.import --skip 1 studentInfo.csv studentInfo
.import --skip 1 studentRegistration.csv studentRegistration
.import --skip 1 studentAssessment.csv studentAssessment
.import --skip 1 studentVle.csv studentVle


/* ============================================================================
   PHẦN 3 — INDEX phục vụ hiệu năng truy vấn (10.6 triệu dòng studentVle)
   ============================================================================ */

CREATE INDEX idx_si_mod_pres   ON studentInfo (code_module, code_presentation);
CREATE INDEX idx_si_student    ON studentInfo (id_student);
CREATE INDEX idx_sr_student    ON studentRegistration (id_student);
CREATE INDEX idx_sa_student    ON studentAssessment (id_student);
CREATE INDEX idx_sa_assessment ON studentAssessment (id_assessment);
CREATE INDEX idx_asm_mod_pres  ON assessments (code_module, code_presentation);
CREATE INDEX idx_svle_student  ON studentVle (id_student);
CREATE INDEX idx_svle_mod_pres ON studentVle (code_module, code_presentation);
CREATE INDEX idx_svle_site     ON studentVle (id_site);
CREATE INDEX idx_vle_mod_pres  ON vle (code_module, code_presentation);


/* ============================================================================
   PHẦN 4 — 7 TRUY VẤN PHÂN TÍCH (tạo insight cho SQL_Insights_Report.xlsx)
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Q1. Kết quả học tập theo từng môn học
-- Insight: môn nào có tỷ lệ bỏ học (Withdrawn) cao nhất, cần ưu tiên can thiệp?
-- ----------------------------------------------------------------------------
SELECT
  code_module,
  COUNT(*) AS total_sinh_vien,
  SUM(CASE WHEN final_result = 'Pass'        THEN 1 ELSE 0 END) AS so_pass,
  SUM(CASE WHEN final_result = 'Distinction' THEN 1 ELSE 0 END) AS so_distinction,
  SUM(CASE WHEN final_result = 'Fail'        THEN 1 ELSE 0 END) AS so_fail,
  SUM(CASE WHEN final_result = 'Withdrawn'   THEN 1 ELSE 0 END) AS so_withdrawn,
  ROUND(100.0 * SUM(CASE WHEN final_result = 'Withdrawn' THEN 1 ELSE 0 END) / COUNT(*), 1)                       AS ty_le_withdrawn_pct,
  ROUND(100.0 * SUM(CASE WHEN final_result IN ('Pass','Distinction') THEN 1 ELSE 0 END) / COUNT(*), 1)           AS ty_le_pass_pct
FROM studentInfo
GROUP BY code_module
ORDER BY ty_le_withdrawn_pct DESC;


-- ----------------------------------------------------------------------------
-- Q2. Mức độ tương tác VLE (tổng click) so với kết quả học tập
-- Insight: sinh viên tương tác nhiều với hệ thống học liệu có kết quả tốt hơn không?
-- ----------------------------------------------------------------------------
WITH engagement AS (
  SELECT code_module, code_presentation, id_student, SUM(sum_click) AS total_click
  FROM studentVle
  GROUP BY code_module, code_presentation, id_student
)
SELECT
  si.final_result,
  COUNT(*)                    AS so_luong_sinh_vien,
  ROUND(AVG(e.total_click),0) AS trung_binh_click,
  MIN(e.total_click)          AS click_thap_nhat,
  MAX(e.total_click)          AS click_cao_nhat
FROM studentInfo si
JOIN engagement e
  ON si.code_module = e.code_module
 AND si.code_presentation = e.code_presentation
 AND si.id_student = e.id_student
GROUP BY si.final_result
ORDER BY trung_binh_click DESC;


-- ----------------------------------------------------------------------------
-- Q3. Thời điểm bỏ học (theo giai đoạn của khóa học)
-- Insight: sinh viên có xu hướng bỏ học vào giai đoạn nào của khóa học?
-- ----------------------------------------------------------------------------
SELECT
  CASE
    WHEN date_unregistration <= 25  THEN '01. Tuần 1-4 (0-25 ngày)'
    WHEN date_unregistration <= 50  THEN '02. Tuần 5-7 (26-50 ngày)'
    WHEN date_unregistration <= 100 THEN '03. Tuần 8-14 (51-100 ngày)'
    WHEN date_unregistration <= 150 THEN '04. Tuần 15-21 (101-150 ngày)'
    ELSE '05. Sau ngày 150'
  END AS giai_doan_bo_hoc,
  COUNT(*) AS so_luong_sinh_vien,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM studentRegistration WHERE date_unregistration IS NOT NULL), 1) AS ty_le_pct
FROM studentRegistration
WHERE date_unregistration IS NOT NULL
GROUP BY giai_doan_bo_hoc
ORDER BY giai_doan_bo_hoc;


-- ----------------------------------------------------------------------------
-- Q4. Kết quả học tập theo IMD Band (chỉ số thiếu thốn khu vực)
-- Insight: sinh viên khu vực khó khăn có bất lợi về kết quả học tập không?
-- ----------------------------------------------------------------------------
SELECT
  CASE WHEN imd_band = '' OR imd_band IS NULL THEN 'Không rõ' ELSE imd_band END AS imd_band,
  COUNT(*) AS so_luong_sinh_vien,
  ROUND(100.0 * SUM(CASE WHEN final_result IN ('Pass','Distinction') THEN 1 ELSE 0 END) / COUNT(*), 1) AS ty_le_pass_pct,
  ROUND(100.0 * SUM(CASE WHEN final_result = 'Withdrawn' THEN 1 ELSE 0 END) / COUNT(*), 1)              AS ty_le_withdrawn_pct
FROM studentInfo
GROUP BY imd_band
ORDER BY imd_band;


-- ----------------------------------------------------------------------------
-- Q5. Thời điểm đăng ký so với khả năng bỏ học
-- Insight: đăng ký sớm/muộn có liên hệ gì đến khả năng bỏ học giữa chừng?
-- ----------------------------------------------------------------------------
SELECT
  CASE
    WHEN sr.date_registration <= -100 THEN '01. Đăng ký rất sớm (<= -100 ngày)'
    WHEN sr.date_registration <= -30  THEN '02. Đăng ký sớm (-99 đến -30 ngày)'
    WHEN sr.date_registration < 0     THEN '03. Đăng ký cận ngày khai giảng (-29 đến -1)'
    ELSE '04. Đăng ký sau khi khai giảng (>= 0 ngày)'
  END AS nhom_thoi_diem_dang_ky,
  COUNT(*) AS so_luong_sinh_vien,
  ROUND(100.0 * SUM(CASE WHEN si.final_result = 'Withdrawn' THEN 1 ELSE 0 END) / COUNT(*), 1)            AS ty_le_withdrawn_pct,
  ROUND(100.0 * SUM(CASE WHEN si.final_result IN ('Pass','Distinction') THEN 1 ELSE 0 END) / COUNT(*), 1) AS ty_le_pass_pct
FROM studentRegistration sr
JOIN studentInfo si
  ON sr.code_module = si.code_module
 AND sr.code_presentation = si.code_presentation
 AND sr.id_student = si.id_student
WHERE sr.date_registration IS NOT NULL
GROUP BY nhom_thoi_diem_dang_ky
ORDER BY nhom_thoi_diem_dang_ky;


-- ----------------------------------------------------------------------------
-- Q6. Điểm trung bình theo loại đánh giá (TMA / CMA / Exam)
-- Insight: loại hình đánh giá nào sinh viên gặp khó khăn nhất?
-- ----------------------------------------------------------------------------
SELECT
  a.code_module,
  a.assessment_type,
  COUNT(sa.score)             AS so_luot_nop,
  ROUND(AVG(sa.score), 1)     AS diem_trung_binh,
  ROUND(100.0 * SUM(CASE WHEN sa.score < 40 THEN 1 ELSE 0 END) / COUNT(sa.score), 1) AS ty_le_diem_duoi_40_pct
FROM studentAssessment sa
JOIN assessments a ON sa.id_assessment = a.id_assessment
WHERE sa.score IS NOT NULL
GROUP BY a.code_module, a.assessment_type
ORDER BY a.code_module, a.assessment_type;


-- ----------------------------------------------------------------------------
-- Q7. Cảnh báo sớm: Engagement 4 tuần đầu so với kết quả cuối cùng
-- Insight: có thể dự báo sớm nguy cơ bỏ học/trượt chỉ dựa vào 4 tuần đầu không?
-- ----------------------------------------------------------------------------
WITH early_engagement AS (
  SELECT code_module, code_presentation, id_student, SUM(sum_click) AS click_4_tuan_dau
  FROM studentVle
  WHERE date BETWEEN 0 AND 27
  GROUP BY code_module, code_presentation, id_student
),
buckets AS (
  SELECT
    si.final_result,
    CASE
      WHEN COALESCE(e.click_4_tuan_dau, 0) = 0  THEN '01. Không tương tác (0 click)'
      WHEN e.click_4_tuan_dau < 20               THEN '02. Thấp (1-19 click)'
      WHEN e.click_4_tuan_dau < 80               THEN '03. Trung bình (20-79 click)'
      ELSE '04. Cao (>=80 click)'
    END AS nhom_engagement_4_tuan_dau
  FROM studentInfo si
  LEFT JOIN early_engagement e
    ON si.code_module = e.code_module
   AND si.code_presentation = e.code_presentation
   AND si.id_student = e.id_student
)
SELECT
  nhom_engagement_4_tuan_dau,
  COUNT(*) AS so_luong_sinh_vien,
  ROUND(100.0 * SUM(CASE WHEN final_result = 'Withdrawn' THEN 1 ELSE 0 END) / COUNT(*), 1)              AS ty_le_withdrawn_pct,
  ROUND(100.0 * SUM(CASE WHEN final_result = 'Fail' THEN 1 ELSE 0 END) / COUNT(*), 1)                    AS ty_le_fail_pct,
  ROUND(100.0 * SUM(CASE WHEN final_result IN ('Pass','Distinction') THEN 1 ELSE 0 END) / COUNT(*), 1)   AS ty_le_pass_pct
FROM buckets
GROUP BY nhom_engagement_4_tuan_dau
ORDER BY nhom_engagement_4_tuan_dau;

/* ============================================================================
   HẾT FILE
   ============================================================================ */
