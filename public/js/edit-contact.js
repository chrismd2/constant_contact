// Edit contact page functionality
(function() {
  const form = document.getElementById('contact-form');
  const loading = document.getElementById('loading');
  const errorAlert = document.getElementById('error-alert');
  const errorMessage = document.getElementById('error-message');
  const successAlert = document.getElementById('success-alert');

  if (!form) return;

  // Get contact ID from URL path
  const pathParts = window.location.pathname.split('/').filter(Boolean);
  // Path should be: contacts/:id/edit
  const contactIdIndex = pathParts.indexOf('contacts');
  const contactId = contactIdIndex >= 0 && pathParts[contactIdIndex + 1] ? pathParts[contactIdIndex + 1] : null;
  
  if (!contactId) {
    console.error('Could not extract contact ID from URL:', window.location.pathname);
    if (loading) loading.classList.add('hidden');
    if (errorAlert) {
      errorAlert.classList.remove('hidden');
      if (errorMessage) {
        errorMessage.textContent = 'Invalid contact ID in URL';
      }
    }
    return;
  }

  // Load contact data
  async function loadContact() {
    try {
      const contact = await apiCall(`/contacts/${contactId}`);
      populateForm(contact);
      if (loading) loading.classList.add('hidden');
      if (form) form.classList.remove('hidden');
    } catch (error) {
      if (loading) loading.classList.add('hidden');
      if (errorAlert) {
        errorAlert.classList.remove('hidden');
        if (errorMessage) {
          errorMessage.textContent = 'Error loading contact: ' + error.message;
        }
      }
      console.error('Error loading contact:', error);
    }
  }

  function populateForm(contact) {
    if (!form) return;

    // Populate name fields
    if (contact.first_name) {
      const firstNameInput = form.querySelector('#first-name');
      if (firstNameInput) firstNameInput.value = contact.first_name;
    }
    if (contact.last_name) {
      const lastNameInput = form.querySelector('#last-name');
      if (lastNameInput) lastNameInput.value = contact.last_name;
    }

    // Populate email
    if (contact.email_address?.address) {
      const emailInput = form.querySelector('#email');
      if (emailInput) emailInput.value = contact.email_address.address;
    }

    // Populate phone
    if (contact.phone_number?.phone_number) {
      const phoneInput = form.querySelector('#phone');
      if (phoneInput) phoneInput.value = contact.phone_number.phone_number;
    }

    // Populate job title
    if (contact.job_title) {
      const jobTitleInput = form.querySelector('#job-title');
      if (jobTitleInput) jobTitleInput.value = contact.job_title;
    }

    // Populate company
    if (contact.company_name) {
      const companyInput = form.querySelector('#company');
      if (companyInput) companyInput.value = contact.company_name;
    }

    // Populate address
    if (contact.street_address) {
      const address = contact.street_address;
      if (address.street) {
        const streetInput = form.querySelector('#street-address');
        if (streetInput) streetInput.value = address.street;
      }
      if (address.city) {
        const cityInput = form.querySelector('#city');
        if (cityInput) cityInput.value = address.city;
      }
      if (address.state_code) {
        const stateInput = form.querySelector('#state');
        if (stateInput) stateInput.value = address.state_code;
      }
      if (address.postal_code) {
        const postalInput = form.querySelector('#postal-code');
        if (postalInput) postalInput.value = address.postal_code;
      }
      if (address.country_code) {
        const countryInput = form.querySelector('#country');
        if (countryInput) countryInput.value = address.country_code;
      }
    }

    // Populate permission to send
    if (contact.email_address?.permission_to_send) {
      const permissionSelect = form.querySelector('#permission-to-send');
      if (permissionSelect) permissionSelect.value = contact.email_address.permission_to_send;
    }
  }

  form.addEventListener('submit', async function(e) {
    e.preventDefault();
    
    // Hide previous alerts
    if (errorAlert) errorAlert.classList.add('hidden');
    if (successAlert) successAlert.classList.add('hidden');

    // Get form data
    const formData = new FormData(form);
    const email = formData.get('email');
    const firstName = formData.get('first-name');
    const lastName = formData.get('last-name');
    const phone = formData.get('phone');
    const jobTitle = formData.get('job-title');
    const company = formData.get('company');
    const streetAddress = formData.get('street-address');
    const city = formData.get('city');
    const state = formData.get('state');
    const postalCode = formData.get('postal-code');
    const country = formData.get('country');
    const permissionToSend = formData.get('permission-to-send') || 'implicit';

    // Build contact data object
    const contactData = {
      email_address: {
        address: email,
        permission_to_send: permissionToSend
      },
      update_source: "Account"
    };

    // Add name if provided
    if (firstName || lastName) {
      if (firstName) contactData.first_name = firstName;
      if (lastName) contactData.last_name = lastName;
    }

    // Add phone if provided
    if (phone) {
      contactData.phone_number = {
        phone_number: phone
      };
    }

    // Add job title if provided
    if (jobTitle) {
      contactData.job_title = jobTitle;
    }

    // Add company if provided
    if (company) {
      contactData.company_name = company;
    }

    // Add address if any address fields are provided
    if (streetAddress || city || state || postalCode || country) {
      const address = {};
      if (streetAddress) address.street = streetAddress;
      if (city) address.city = city;
      if (state) address.state_code = state;
      if (postalCode) address.postal_code = postalCode;
      if (country) address.country_code = country;

      contactData.street_address = address;
    }

    try {
      // Disable submit button
      const submitBtn = form.querySelector('button[type="submit"]');
      const originalText = submitBtn.textContent;
      submitBtn.disabled = true;
      submitBtn.textContent = 'Updating...';

      await apiCall(`/contacts/${contactId}`, {
        method: 'PUT',
        body: JSON.stringify(contactData),
      });

      // Show success message
      if (successAlert) {
        successAlert.classList.remove('hidden');
      }

      // Scroll to top to show success message
      window.scrollTo({ top: 0, behavior: 'smooth' });

      // Re-enable submit button
      submitBtn.disabled = false;
      submitBtn.textContent = originalText;

    } catch (error) {
      // Show error message
      if (errorAlert) {
        errorAlert.classList.remove('hidden');
        if (errorMessage) {
          errorMessage.textContent = error.message;
        }
      }

      // Re-enable submit button
      const submitBtn = form.querySelector('button[type="submit"]');
      submitBtn.disabled = false;
      submitBtn.textContent = 'Update Contact';

      // Scroll to top to show error message
      window.scrollTo({ top: 0, behavior: 'smooth' });

      console.error('Error updating contact:', error);
    }
  });

  // Load contact on page load
  loadContact();
})();
