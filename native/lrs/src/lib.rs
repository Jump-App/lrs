use rustler::Error;

fn build_suffix_array(chars: &[char]) -> Vec<usize> {
    let mut indices: Vec<usize> = (0..chars.len()).collect();
    indices.sort_by(|&i, &j| chars[i..].cmp(&chars[j..]));
    indices
}

fn compute_lcp(chars: &[char], suffix_array: &[usize]) -> Vec<usize> {
    let n = suffix_array.len();
    let mut lcp = vec![0; n];
    let mut inv_suff = vec![0; n];

    // Fill values in inv_suff[]
    for i in 0..n {
        inv_suff[suffix_array[i]] = i;
    }

    let mut k = 0;
    for i in 0..n {
        if inv_suff[i] == n - 1 {
            k = 0;
            continue;
        }

        let j = suffix_array[inv_suff[i] + 1];

        while i + k < n && j + k < n && chars[i + k] == chars[j + k] {
            k += 1;
        }

        lcp[inv_suff[i]] = k;

        if k > 0 {
            k -= 1;
        }
    }

    lcp
}

#[rustler::nif]
fn longest_repeating_substring(input: String) -> Result<String, Error> {
    let chars: Vec<char> = input.chars().collect();
    let suffix_array = build_suffix_array(&chars);
    let lcp = compute_lcp(&chars, &suffix_array);

    let mut max_len = 0usize;
    let mut start_index = 0usize;

    // Iterate over the LCP array to find the maximum length of a repeating substring.
    for i in 0..lcp.len() - 1 {
        if lcp[i] > max_len {
            max_len = lcp[i];
            start_index = suffix_array[i];
        }
    }

    if max_len > 0 {
        Ok(chars[start_index..start_index + max_len].iter().collect())
    } else {
        Ok("".to_string())
    }
}

rustler::init!("Elixir.LRS", [longest_repeating_substring]);