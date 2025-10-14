// Prevent duplicate class declaration
if (typeof AiHelperMarkdownParser === "undefined") {
  window.AiHelperMarkdownParser = class {
    constructor() {
      this.rules = [
        // Headers
        {
          pattern: /^(#{1,6})\s(.+)$/gm,
          replacement: (match, hashes, content) => {
            const level = hashes.length;
            return `<h${level}>${content.trim()}</h${level}>`;
          }
        },
        // Bold
        {
          pattern: /\*\*(.+?)\*\*/g,
          replacement: (match, content) => `<strong>${content}</strong>`
        },
        // Italic
        {
          pattern: /\*(.+?)\*/g,
          replacement: (match, content) => `<em>${content}</em>`
        },
        // Links
        {
          pattern: /\[(.+?)\]\((.+?)\)/g,
          replacement: (match, text, url) => `<a href="${url}">${text}</a>`
        },
        // Unordered lists
        {
          pattern: /^\s*[-*+]\s+(.+)$/gm,
          replacement: (match, content) => `<li>${content}</li>`
        },
        // Ordered lists
        {
          pattern: /^\s*\d+\.\s+(.+)$/gm,
          replacement: (match, content) => `<li>${content}</li>`
        },
        // Code blocks
        {
          pattern: /```([^`]+)```/g,
          replacement: (match, content) => `<pre><code>${content}</code></pre>`
        },
        // Inline code
        {
          pattern: /`([^`]+)`/g,
          replacement: (match, content) => `<code>${content}</code>`
        },
        // Paragraphs - exclude HTML tags and empty lines
        {
          pattern: /^(?!<[a-z\/])(?!$).+$/gm,
          replacement: match => `<p>${match}</p>`
        }
      ];
    }

    parse(markdown) {
      let html = markdown;

      // Process tables first
      html = this.processTables(html);

      // Process lists
      html = this.processLists(html);

      // Apply all other rules except list-related rules (already processed)
      this.rules.forEach(rule => {
        // Skip list-related patterns as they've already been processed
        const isListPattern =
          rule.pattern.source &&
          (rule.pattern.source.includes("[-*+]\\s") ||
            rule.pattern.source.includes("\\d+\\.\\s"));
        if (!isListPattern) {
          html = html.replace(rule.pattern, rule.replacement);
        }
      });

      return html;
    }

    processTables(markdown) {
      const tableRegex = /^\|(.+)\|$/;
      const headerSeparatorRegex = /^\|(\s*:?-+:?\s*\|)+$/;

      const lines = markdown.split("\n");
      let html = [];
      let inTable = false;
      let tableData = [];
      let alignments = [];

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const isTableRow = tableRegex.test(line);
        const isHeaderSeparator = headerSeparatorRegex.test(line);

        if (isTableRow) {
          if (!inTable) {
            inTable = true;
            tableData = [];
            alignments = [];
          }

          // Process the row data
          const cells = line
            .split("|")
            .filter(cell => cell.trim() !== "")
            .map(cell => cell.trim());

          tableData.push(cells);

          // If next line is a header separator, process alignment
          if (i + 1 < lines.length && headerSeparatorRegex.test(lines[i + 1])) {
            const separators = lines[i + 1]
              .split("|")
              .filter(sep => sep.trim() !== "")
              .map(sep => sep.trim());

            alignments = separators.map(sep => {
              if (sep.startsWith(":") && sep.endsWith(":")) return "center";
              if (sep.endsWith(":")) return "right";
              if (sep.startsWith(":")) return "left";
              return "left";
            });
            // Skip the separator line
            i++;
          }
        } else {
          if (inTable) {
            // Convert table data to HTML
            html.push(this.convertTableToHtml(tableData, alignments));
            inTable = false;
            tableData = [];
            alignments = [];
          }

          // Only add non-separator lines
          if (!isHeaderSeparator) {
            html.push(line);
          }
        }
      }

      // Handle table at end of document
      if (inTable) {
        html.push(this.convertTableToHtml(tableData, alignments));
      }

      return html.join("\n");
    }

    convertTableToHtml(tableData, alignments) {
      if (tableData.length === 0) return "";

      let html = ['<table class="list">'];

      // Add header row
      html.push("<thead>");
      html.push("<tr>");
      tableData[0].forEach((cell, index) => {
        const alignment = alignments[index] || "left";
        const alignAttr = alignment !== "left" ? ` align="${alignment}"` : "";
        html.push(`<th${alignAttr}>${cell}</th>`);
      });
      html.push("</tr>");
      html.push("</thead>");

      // Add body rows
      if (tableData.length > 1) {
        html.push("<tbody>");
        for (let i = 1; i < tableData.length; i++) {
          html.push("<tr>");
          tableData[i].forEach((cell, index) => {
            const alignment = alignments[index] || "left";
            const alignAttr =
              alignment !== "left" ? ` align="${alignment}"` : "";
            html.push(`<td${alignAttr}>${cell}</td>`);
          });
          html.push("</tr>");
        }
        html.push("</tbody>");
      }

      html.push("</table>");
      return html.join("\n");
    }

    processLists(markdown) {
      const lines = markdown.split("\n");
      let html = [];
      let listStack = []; // Stack to manage nested lists: [{type: 'ol'|'ul', indent: number}]
      let emptyLineCount = 0;

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const unorderedMatch = line.match(/^(\s*)[-*+]\s+(.+)$/);
        const orderedMatch = line.match(/^(\s*)(\d+)\.\s+(.+)$/);
        const isEmpty = line.trim() === "";

        if (unorderedMatch || orderedMatch) {
          const indent = (unorderedMatch || orderedMatch)[1].length;
          const currentListType = unorderedMatch ? "ul" : "ol";
          const content = unorderedMatch ? unorderedMatch[2] : orderedMatch[3];

          // Determine current indent level
          let currentLevel = Math.floor(indent / 2); // Assume 2 spaces per level

          // Close deeper nested lists if we're back at a shallower level
          while (
            listStack.length > 0 &&
            listStack[listStack.length - 1].indent > currentLevel
          ) {
            const closingList = listStack.pop();
            html.push(`</${closingList.type}>`);
            // If we have a parent list, close the parent's li tag
            if (listStack.length > 0) {
              html.push("</li>");
            }
          }

          // Close same-level list if type changes
          if (
            listStack.length > 0 &&
            listStack[listStack.length - 1].indent === currentLevel &&
            listStack[listStack.length - 1].type !== currentListType
          ) {
            const closingList = listStack.pop();
            html.push(`</${closingList.type}>`);
            if (listStack.length > 0) {
              html.push("</li>");
            }
          }

          // Open new nested list if indent level increased
          if (
            listStack.length === 0 ||
            listStack[listStack.length - 1].indent < currentLevel
          ) {
            html.push(`<${currentListType}>`);
            listStack.push({ type: currentListType, indent: currentLevel });
          } else if (
            listStack.length > 0 &&
            listStack[listStack.length - 1].indent === currentLevel
          ) {
            // Same level - close previous li if it exists
            if (html[html.length - 1] !== `<${currentListType}>`) {
              html.push("</li>");
            }
          }

          html.push(`<li>${content}`);
          emptyLineCount = 0;
        } else if (isEmpty && listStack.length > 0) {
          // Count consecutive empty lines
          emptyLineCount++;

          // Close all lists after 2+ consecutive empty lines
          const isLastLine = i === lines.length - 1;
          const nextLine = i + 1 < lines.length ? lines[i + 1] : "";
          const nextIsListItem = /^\s*[-*+]|\d+\./.test(nextLine);

          if (emptyLineCount >= 2 || (isLastLine && !nextIsListItem)) {
            // Close all open list items and lists
            while (listStack.length > 0) {
              html.push("</li>");
              const closingList = listStack.pop();
              html.push(`</${closingList.type}>`);
            }
            emptyLineCount = 0;
            html.push(line);
          }
          // Skip adding empty lines while in list to prevent paragraph conversion
        } else {
          // Non-empty, non-list line
          if (listStack.length > 0) {
            // Close all open lists
            while (listStack.length > 0) {
              html.push("</li>");
              const closingList = listStack.pop();
              html.push(`</${closingList.type}>`);
            }
            emptyLineCount = 0;
          }
          html.push(line);
        }
      }

      // Close any remaining open lists
      while (listStack.length > 0) {
        html.push("</li>");
        const closingList = listStack.pop();
        html.push(`</${closingList.type}>`);
      }

      return html.join("\n");
    }
  };
}
