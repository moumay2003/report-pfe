# Snowflake Environment Alignment & CI/CD Pipeline
## End-of-Studies Internship Report — LaTeX Project

**Author**: Mouad Moulay Rachid  
**Organization**: IBM CIC Morocco / Hakkoda  
**Client**: ARYZTA  
**Academic Year**: 2024–2025  

---

## File Structure

```
latex_report/
├── main.tex                    ← Main entry point (compile this)
├── 00-coverpage.tex            ← Cover page
├── 01-dedication.tex           ← Dedication
├── 02-acknowledgements.tex     ← Acknowledgements
├── 03-abstract.tex             ← Abstract (EN + FR)
├── 05-general-introduction.tex ← General Introduction
├── 06-chapter1-context.tex     ← Chapter 1: General Context
├── 07-chapter2-analysis.tex    ← Chapter 2: Problem Analysis
├── 11-general-conclusion.tex   ← General Conclusion
├── appendices.tex              ← Appendices (A, B, C)
├── glossary.tex                ← Acronyms & glossary entries
├── bibliography.bib            ← BibTeX references
├── images/                     ← Place logos and figures here
└── README.md
```

## Chapters to Add Later

Uncomment in `main.tex` when ready:
- `08-chapter3-design.tex`     — Solution Design
- `09-chapter4-implementation.tex` — CI/CD Implementation
- `10-chapter5-results.tex`    — Results & Evaluation

## Compilation

Use **pdflatex + bibtex + makeglossaries**:

```bash
pdflatex main.tex
bibtex main
makeglossaries main
pdflatex main.tex
pdflatex main.tex
```

Or with **latexmk**:

```bash
latexmk -pdf -shell-escape main.tex
```

## Required Packages

All packages are standard TeX Live / MiKTeX. Key ones:
- `pgfgantt` — Gantt chart
- `listings` — Code blocks
- `tcolorbox` — Callout boxes
- `longtable` — Multi-page tables
- `pifont` — Checkmarks/crosses (✓✗)
- `pdflscape` — Landscape pages
- `glossaries` — Acronym list
- `natbib` — Bibliography

## Images

Place logo files in `images/` and uncomment the `\includegraphics` lines in `00-coverpage.tex`:
- `images/ensias-logo.png`
- `images/ibm-logo.png`
- `images/hakkoda-logo.png`

Figure placeholders throughout the document indicate where architecture diagrams,
screenshots, and charts should be inserted.
