// Theme toggle functionality
(function() {
  const themeToggle = document.getElementById('theme-toggle');
  if (!themeToggle) return;

  // Check for saved theme preference or default to light mode
  const currentTheme = localStorage.getItem('theme') || 'light';
  if (currentTheme === 'dark') {
    document.documentElement.classList.add('dark');
  }

  themeToggle.addEventListener('click', function() {
    const isDark = document.documentElement.classList.toggle('dark');
    localStorage.setItem('theme', isDark ? 'dark' : 'light');
  });
})();

// API base URL - auto-detect from current path or use environment variable
// When deployed behind nginx at /constant_contact/, we need to use that prefix
function detectApiBase() {
  // First, check if explicitly set via window.API_BASE_URL
  if (typeof window.API_BASE_URL === 'string' && window.API_BASE_URL.trim() !== '') {
    const base = window.API_BASE_URL.trim();
    // Ensure it ends with / unless it's root
    return base === '/' ? '/' : (base.endsWith('/') ? base : base + '/');
  }
  
  // Default to root for standalone deployment
  return '/';
}

const API_BASE = detectApiBase();
// Make it globally accessible for other scripts
window.API_BASE = API_BASE;


// Helper function to make API calls
async function apiCall(endpoint, options = {}) {
  const defaultOptions = {
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  };

  // Normalize endpoint path - ensure proper joining
  const normalizedEndpoint = endpoint.startsWith('/') ? endpoint : '/' + endpoint;
  // If API_BASE is not root, strip leading slash from endpoint to avoid double slashes
  const url = API_BASE === '/' ? normalizedEndpoint : API_BASE + normalizedEndpoint.substring(1);

  let response;
  try {
    response = await fetch(url, {
      ...defaultOptions,
      ...options,
      headers: {
        ...defaultOptions.headers,
        ...options.headers,
      },
    });
  } catch (error) {
    // Handle network errors (CORS, connection refused, etc.)
    console.error('Network error fetching:', url, error);
    throw new Error(`Network error: ${error.message}. Please check your connection and ensure the server is running.`);
  }

  // Handle 204 No Content responses (common for DELETE requests)
  if (response.status === 204) {
    return null; // Success with no content
  }

  // Check if response is actually JSON before parsing
  const contentType = response.headers.get('content-type');
  if (!contentType || !contentType.includes('application/json')) {
    const text = await response.text();
    throw new Error(`Expected JSON but got ${contentType}. Response: ${text.substring(0, 100)}`);
  }

  const data = await response.json();
  
  if (!response.ok) {
    // Handle different error response formats
    let errorMessage = `API error: ${response.status}`;
    if (Array.isArray(data) && data.length > 0) {
      // Constant Contact returns errors as an array
      errorMessage = data.map(err => err.error_message || err.error_key || JSON.stringify(err)).join(', ');
    } else if (data.error) {
      errorMessage = data.error.message || data.error.error_message || JSON.stringify(data.error);
    } else if (data.error_message) {
      errorMessage = data.error_message;
    }
    throw new Error(errorMessage);
  }

  return data;
}

// Format date helper
function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

// Format phone number helper
function formatPhone(phone) {
  if (!phone) return 'N/A';
  // Simple formatting - can be enhanced
  return phone;
}
